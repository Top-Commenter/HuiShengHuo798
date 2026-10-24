# 慧生活798 无广告自定义版

一个基于 Flutter 的个人学习项目，重新实现了「慧生活798」校园水控客户端的常用功能：查询设备、扫码/取水、实时费用、账单与每日饮水统计。

> **本项目仅供学习与技术研究，不用于任何商业用途。** 详见文末[免责声明](#免责声明)。

- 当前版本：`1.0.0+4`（版本记录见 [docs/CHANGELOG.md](docs/CHANGELOG.md)）
- 参考项目：[KazemiyaMione/huish](https://github.com/KazemiyaMione/huish)

## 功能

| 模块 | 说明 |
| --- | --- |
| 设备 | 首页展示已绑定设备列表、运行状态；点击进入设备详情 |
| 取水 | 开始 / 停止取水，1 秒轮询，实时显示「本次接水」升数与「实时费用」（单价由本设备历史账单反推） |
| 每日饮水 | 首页看板：今日饮水总量 + 近 7 天柱状图，**仅统计直饮机**，排除淋浴器/水表，只计已付款账单 |
| 账单 | 消费记录列表（按量 / 按次、状态、金额），支持账单详情 |
| 钱包 | 余额与充值相关入口 |
| 积分 | 积分与签到（可在设置中隐藏该模块） |
| 我的 | 账号信息、钱包、深色模式、积分模块开关、关于（版本号 / 历史更新 / 源码地址） |

## 技术栈

- Flutter（Dart SDK `^3.13.5`）+ Provider 状态管理
- `http` 请求封装（含请求签名 `lib/utils/sign_utils.dart`）
- `shared_preferences` 本地缓存（账号、设备、饮水明细）
- `url_launcher` 打开外部链接

## 项目结构

```
lib/
├── main.dart                 # 入口：Provider 注入 + 路由
├── app_info.dart             # 版本号与仓库/参考项目链接
├── api/
│   ├── api_client.dart       # 接口封装（登录、设备、账单、钱包、积分）
│   ├── water_stats.dart      # 每日饮水量统计（直饮机账单 → 明细升数 → 7 天聚合）
│   └── ...
├── providers/                # AuthProvider / SettingsProvider
├── screens/                  # 登录、首页、设备、账单、钱包、积分、我的、关于
├── theme/app_theme.dart      # 主题（主色 #2E9E8F，浅色/深色）
└── utils/sign_utils.dart     # 请求签名
docs/
└── CHANGELOG.md              # 版本更新记录（同时打包进 App 的「关于」页）
```

## 本地运行

```bash
flutter pub get
flutter run                 # 调试运行
flutter build apk --release # 构建安装包
```

> 构建产物（`*.apk` / `*.aab`、`build/`）已在 `.gitignore` 中排除，不纳入版本管理。

## 更新日志

所有版本变更记录在 [docs/CHANGELOG.md](docs/CHANGELOG.md)，并在 App「我的 → 关于」内可折叠查看。
约定：每次发版在文件顶部追加一条记录，同时递增 `pubspec.yaml` 的版本号与 `lib/app_info.dart` 的 `kAppVersion`。

## 免责声明

1. **学习用途**：本项目为个人学习 Flutter、网络请求与界面实现的练习作品，**仅供学习交流，严禁用于任何商业用途**。
2. **无官方关联**：本项目为第三方个人作品，与「惠生活798」官方及其运营方**没有任何关联**，不代表官方立场。
3. **风险自负**：使用本项目产生的一切费用、数据异常、账号风险及其他后果，由使用者自行承担；请自行评估并遵守相关服务条款与法律法规。
4. **数据来源**：项目仅调用公开的客户端接口，不存储、不传播任何用户数据；本地缓存仅保存在使用者自己的设备上。
5. **权利声明**：如相关权利方认为本项目存在侵权内容，请联系删除，本项目将立即停止分发相关内容。

## 致谢

- 参考项目：[huish](https://github.com/KazemiyaMione/huish)，本项目在其思路基础上以 Flutter 重新实现。
