# 健康属性档案接口（像素 Demo）

本页保留旧版 0—100 五属性 JSON，供尚未绑定报告的模拟角色兼容使用。真实报告已接入，见 `health-entry-integration.md`。报告档案锁定后不接受旧版手工模拟更新。旧格式调用 `GameState.apply_health_profile(payload)`。调用方成功后应保存档案、刷新界面；界面 JSON 导入入口已经完成这些操作。

示例文件：`data/health-profile.example.json`。

```json
{
  "profile_id": "demo-songfeng",
  "revision": 1,
  "source": "模拟健康档案",
  "simulated": true,
  "attributes": {
    "life": 45,
    "attack": 40,
    "defense": 35,
    "spirit": 50,
    "stamina": 40
  }
}
```

- 五项属性缺一不可，每项为 0—100 的有限数值。拒绝字符串、布尔值、缺失项和越界值，验证失败时不会部分更新角色。
- `profile_id` 标识档案，`revision` 是正整数。同一档案只接受更高版本；允许后续评估提高或降低属性。
- `source` 用于显示来源；`simulated` 必须如实标识模拟数据。
- 应用新档案保留修为、已通关记录和技能解锁。正在进行的战斗使用入场时的属性快照，下一场使用新属性。
- 不保存原始病历、报告内容、姓名、身份证或诊断。本地不根据评分自动判定疾病或死亡。

`HealthProfile.battle_stats()` 只负责属性到游戏资源与伤害的暂定换算，可以独立调参。它不是健康评估算法。后续真实服务的评分方法、身份验证与传输由服务接入任务另行实现。

存档 schema 4 兼容旧修为、计划、家庭确认与恢复篇章。旧存档迁移前保存 `*-before-corridor-v4.json` 备份。运行版本使用独立的 `user://songfeng_pixel_progress.json`；首次可读取旧运行存档后迁移，后续不写旧文件。

当前新增 `cleared_bosses`、`boss_records` 和 `selected_boss_id`；健康档案更新同样保留这三个字段。旧版五属性试炼记录保留以兼容既有技能解锁，不自动冒充二十 Boss 的首通。
