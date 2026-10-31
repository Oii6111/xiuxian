"""健康域审核入口。模型和老人聊天不能直接指定奖励或触发游戏结算。"""
import importlib.util
import hmac
import os
from pathlib import Path

from flask import jsonify, request

_spec = importlib.util.spec_from_file_location("game_task_bridge", Path(__file__).resolve().parent.parent / "wechat-bridge/game_task_bridge.py")
bridge = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bridge)


def register_game_routes(app, database):
    @app.post("/internal/v1/game/verified-events")
    def verified_event():
        # 独立审核凭证不提供给聊天 hook；老人确认识别文本不等于审核了任务证据。
        expected = os.environ.get("GAME_REVIEW_TOKEN", "")
        provided = request.headers.get("Authorization", "")
        if not expected or not hmac.compare_digest(provided, "Bearer " + expected):
            return jsonify({"ok": False, "code": "UNAUTHORIZED"}), 401
        payload = request.get_json(silent=True)
        fields = {"binding_id", "task_instance_id", "event_id", "verification_level", "evidence_confirmed"}
        if (not isinstance(payload, dict) or set(payload) != fields
                or payload["evidence_confirmed"] is not True
                or any(not isinstance(payload[key], str) or not payload[key] for key in fields - {"evidence_confirmed"})):
            return jsonify({"ok": False, "code": "INVALID_PAYLOAD"}), 400
        try:
            route = bridge.route_for(payload["binding_id"])
            with database() as conn:
                event = conn.execute("SELECT * FROM health_events WHERE event_id = ?", (payload["event_id"],)).fetchone()
                identity = conn.execute("SELECT * FROM game_event_identity WHERE event_id = ?", (payload["event_id"],)).fetchone()
            if (not event or not identity or not event["family_share"] or event["elder_id"] != route["elder_id"]
                    or identity["sender_id"] != route["sender_id"]
                    or identity["channel_account_id"] != route["channel_account_id"]):
                raise bridge.BridgeError("EVENT_NOT_AUTHORIZED")
            # 照片记录仅允许审核员确认其确实满足指定任务后按 photo 提交。
            # 设备及家属确认需要专门的真实证据适配器，不能在这里升档。
            allowed = {"photo_observation": {"photo"}, "measurement": {"self_report"},
                       "medication_taken": {"self_report"}, "step_record": {"self_report"}}
            if payload["verification_level"] not in allowed.get(event["event_type"], set()):
                raise bridge.BridgeError("UNSUPPORTED_EVIDENCE")
            result = bridge.submit_confirmed(route["binding_id"], payload["task_instance_id"],
                event["event_id"], event["created_at"], payload["verification_level"],
                identity["sender_id"], identity["channel_account_id"])
            return jsonify({"ok": True, "data": result})
        except (bridge.BridgeError, ValueError) as error:
            return jsonify({"ok": False, "code": str(error)}), 409
        except OSError:
            return jsonify({"ok": False, "code": "GAME_UNAVAILABLE_RETRY"}), 503
