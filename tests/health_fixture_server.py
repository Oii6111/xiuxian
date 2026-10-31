"""Local HTTP contract fixture on 8001. Never invokes a real model."""
from pathlib import Path
import sys
import os
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "health-entry"))
import server

if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="xiuxian-contract-") as storage:
        test_port = int(os.environ.get("XIUXIAN_HEALTH_TEST_PORT", "8001"))
        server.BASELINE_DIR = storage
        server.recognizer.load_config = lambda: ("fixture", f"http://127.0.0.1:{test_port}", "test-fixture")
        server.recognizer.recognize_medical_report = lambda *_args: {
            "title": "HTTP contract fixture", "groups": [{"title": "Fixture", "items": [
                {"label": "测试指标", "value": "50", "status": "unknown"}]}]}
        server.app.run(host="127.0.0.1", port=test_port, debug=False)
