# 支付快捷动作

本分支在“设置 > 操作按钮”右上角增加了“快捷动作”菜单：

- 系统动作
- 微信扫一扫
- 微信付款码
- 支付宝扫一扫
- 支付宝付款码

选择顺序仍然是：先选单击/双击/长按，再选方向，最后选快捷动作。

动作保存在 `com.huami.actiongesture` 的 `customAction.<gesture>.<direction>` 偏好中。选择“系统动作”会回到原有系统动作执行路径。

当前默认 URL scheme：

```text
weixin://scanqrcode
weixin://pay
alipayqr://platformapi/startapp?saId=10000007
alipayqr://platformapi/startapp?saId=20000056
```

付款码入口属于第三方 App 的非稳定 deep link；如果某个版本无效，需要只修改 `executeCustomAction:` 中的 URL，不要改动系统动作归档逻辑。

编译安装后必须重载 SpringBoard：

```sh
sbreload
```

如果动作无反应，优先检查：目标 App 是否安装并已登录、URL scheme 是否仍受支持、当前是否处于锁屏/受限场景，以及是否安装了正确的 rootful/rootless/RootHide 包。
