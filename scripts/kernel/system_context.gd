extends RefCounted
## 显式依赖容器，仅注入系统层；UI 不获取此对象，不通过全局节点查找服务。
var clock: RefCounted
var events: RefCounted
var random: RefCounted
var registry: RefCounted
var store: RefCounted
var audit: RefCounted
