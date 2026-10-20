# music163_cads

网易云音乐 iOS 去广告插件，正式版本 **2.0.0**。

在网易云音乐「设置」中，点击「账号与安全」上方的 **music163_cads** 进入插件设置。插件面板适配源 App 的条目高度、字体、颜色、开关与返回操作。

[下载最新版](https://github.com/lcmovie/music163_cads/releases/latest) · [发行记录](https://github.com/lcmovie/music163_cads/releases)

## 适配环境

- 网易云音乐 **9.6.09（7516）**。
- 当前测试环境：**iOS 16.0 / ARM64 / TrollStore / TrollFools**。
- 其他 App 或系统版本尚未验证；编译目标的最低系统版本不代表实际验证范围。

## 功能

提供去广告总开关及以下独立模块：

- 开屏广告
- 首页横幅广告
- 信息流插入广告
- 搜索页广告
- 评论区广告
- 播客／语音广告
- 分享面板广告
- 直播礼物墙广告
- 激励视频（全部拦截）

另有「屏蔽推送权限弹窗」「屏蔽运营／引导弹窗」两个开关，独立于去广告总开关生效。

首次安装所有开关默认关闭。开启总开关后，分模块按各自开关生效；升级保留已有 v2 开关配置。未匹配到适配入口的模块不可开启。

开屏处理包含启动、后台返回及缓存素材处理路径，不清除歌曲缓存或登录数据。屏蔽激励视频不会获得观看奖励；屏蔽推送权限弹窗不会撤销已授予的系统权限。部分隐藏的广告位置可能保留空白。

## 安装与升级

1. 从 [Releases](https://github.com/lcmovie/music163_cads/releases/latest) 下载 `music163_cads-2.0.0.dylib`，或下载同版本压缩包后解压。
2. 在 TrollFools 中移除旧版 `music163_cads` 注入项，再注入新版 dylib，避免重复加载。无需重装 App 或清除数据。
3. 完全退出网易云音乐后重新打开，进入「设置 → music163_cads」。
4. 按需开启总开关与分模块开关。开屏效果请在完全退出后再次启动时检查。

发行包不包含网易云音乐 IPA、签名证书或注入工具。

## 插件内检查更新

点击「插件版本」会比较本机版本与本仓库的公开发行版；发现新版后，该条目显示红色提醒。进入插件设置也会自动检查，15 分钟内复用检查结果；手动点击可主动检查。

点击「仓库地址」可打开本仓库。更新检查只提示并提供发行版入口，不会自动安装。请求使用 GitHub 公开 API，不携带 App 账号、Cookie 或授权令牌。

## 从源码构建

提供 Windows 构建脚本，需要 Python 3、带 Mach-O 链接器的 LLVM（参考版本 22.1.8），以及自行准备的 iPhoneOS 16.5 SDK。SDK 和工具链不随源码分发。

在项目根目录执行，路径替换为自己的安装位置：

```powershell
$env:NC_LLVM_BIN = 'C:\LLVM\bin'
$env:NC_IOS_SDK = 'C:\SDK\iPhoneOS16.5.sdk'
py -X utf8 .\build.py
py -X utf8 .\tools\test_artifact_audit.py
py -X utf8 .\tools\test_version_compare.py
py -X utf8 .\tools\test_menu_geometry.py
py -X utf8 .\tools\test_home_policy.py
py -X utf8 .\tools\run_static_analysis.py
```

产物位于 `build/2.0.0/`。标准 Clang / LLD 生成 ARM64 dylib 和 ad-hoc 签名，不对链接后的二进制手工修补。构建脚本会检查 Mach-O 加载命令、绑定数据、LINKEDIT 范围及签名页哈希。

`test_artifact_audit.py` 默认运行 5 个自包含回归用例，另有 1 个可选旧产物用例，由 `NC_TEST_LEGACY_ARTIFACT` 环境变量指定。首页策略测试中读取原 App 数据的用例会在未提供样本时跳过。版本比较和菜单布局测试在 Windows 上编译并调用相同 C 源码的测试 DLL。

公开源码仅包含 `Sources/`、构建脚本、测试工具和说明文档，不包含原 App、设备日志或本地工具链。静态检查不能替代具体设备与广告场景的验证。
