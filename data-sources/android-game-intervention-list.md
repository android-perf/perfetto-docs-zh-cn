# Android 游戏干预列表

_此数据源仅在 Android userdebug 构建上受支持。_

"android.game_interventions" 数据源收集每个游戏的可用游戏模式和游戏干预列表。

这允许你更好地比较或采集同一游戏但在不同游戏模式或具有不同游戏干预下的 trace。

### UI

在 UI 级别，游戏干预作为 trace 信息页中的表格显示。

![](/docs/images/android_game_interventions.png "UI 中的 Android 游戏干预列表")

### SQL

在 SQL 级别，游戏干预数据写入以下表：

- [`android_game_intervention_list`](docs/analysis/sql-tables.autogen#android_game_intervention_list)

以下是查询支持的模式（带有干预）和每个游戏的当前游戏模式的示例。

```sql
select package_name, current_mode, standard_mode_supported, performance_mode_supported, battery_mode_supported
from android_game_intervention_list
order by package_name
```
package_name | current_mode | standard_mode_supported | performance_mode_supported | battery_mode_supported
-------------|--------------|-------------------------|---------------------------|-----------------------
com.supercell.clashofclans | 1 | 1 | 0 | 1
com.mobile.legends | 3 | 1 | 0 | 1
com.riot.league.wildrift | 1 | 1 | 0 | 1

### TraceConfig

Android 游戏干预列表通过 trace 配置的 [AndroidGameInterventionListConfig](/docs/reference/trace-config-proto.autogen#AndroidGameInterventionListConfig) 部分进行配置。

示例配置：

```protobuf
data_sources: {
 config {
 name: "android.game_interventions"
 android_game_intervention_list_config {
 package_name_filter: "com.my.game1"
 package_name_filter: "com.my.game2"
 }
 }
}
```
