技能搜索库 v0.1.0
=================
署名：公会-太阳神殿-yanz

命令：
  /ssl
  /spellsearch

需要：
  支持 UnitXP("spellsearch", query, limit) 的 UnitXP_SP3.dll。

搜索：
  - 中文技能名
  - 英文技能名
  - SpellID（数字直接查询）
  - 只在点击“搜索”或按 Enter 时执行，不边输入边扫描。

结果：
  左侧为匹配技能；右侧展示 Spell.dbc 字段。
  基础页同时尝试解析 rangeIndex / durationIndex / radiusIndex1~3 的实际数值。
  当前 API 没有 SpellCastTimes.dbc 查询接口，因此 castingTimeIndex 仅显示原始索引。
