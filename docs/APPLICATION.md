# 2026 MoonBit 黑客松项目申报书

## 一、基本信息
- 项目名称：MoonSpell
- 申报人：GitHub ID `wccerty`，姓名【待填写】
- 参赛形式：个人
- 项目方向：新生态项目建设
- GitHub：https://github.com/wccerty/moonspell
- 许可证：Apache-2.0；当前仓库已有 32 个有效 commits

## 二、项目简介
MoonSpell 是纯 MoonBit 实现的 Hunspell 兼容拼写检查引擎，直接读取 `.aff/.dic` 词典，完成词条解析、词缀推导、复合词判断和候选建议。
项目不调用 C++ Hunspell，也不依赖外部进程，目标是在 MoonBit、WASM 和原生应用中复用同一套拼写检查能力。

## 三、通用性说明
- 词典通用：支持 Hunspell 格式词典和不同 flag、词缀、复合词配置。
- 集成通用：提供 MoonBit 库 API 和 `validate/check/suggest` 等 CLI。
- 平台通用：核心不依赖桌面系统，可用于 native、WASM 和浏览器本地检查。
- 边界透明：不支持的 directive 会保留诊断，不静默忽略或虚假声明完全兼容。

## 四、核心功能
- 解析 `.dic` 词条、flags、morphology，以及 `.aff` 的 `SET/FLAG/AF/AM/TRY/WORDCHARS` 等配置。
- 实现 PFX/SFX、条件、strip/add、cross product、continuation flags 和复杂前缀。
- 实现 `NEEDAFFIX/FORBIDDENWORD/KEEPCASE/CHECKSHARPS` 及核心复合词规则。
- 实现 `REP/MAP/PHONE/ph:/NGRAM` 和编辑距离候选，并完成验证、去重和排序。
- 提供 fixture runner、Markdown 兼容报告、单元测试、CI 和 native release 构建。

## 五、预期使用场景
1. 编辑器实时检查：输入 `exsample`，返回拒绝并给出 `example` 等候选。
2. 文档平台批量校对：加载 en_US 词典检查正文，输出错误位置和修改建议。
3. 企业术语库：在自定义词典中加入产品名，MoonSpell 按领域词典接受或拒绝术语。
4. 社区内容审核：发布前检查标题和评论，减少明显拼写错误。
5. 兼容性测试工具：运行官方 `.good/.wrong/.sug` fixture，生成可复现兼容报告。

## 六、项目性质与来源
MoonSpell 是独立开发的原创 MoonBit 项目。Hunspell v1.7.3 仅作为格式规范和测试行为参考，仓库不包含 Hunspell C++ 源码，也不通过 C FFI 包装其实现。
参考链接：https://github.com/hunspell/hunspell 。如后续引入第三方代码、fixture 或词典，将保留原版权和许可证声明。

## 七、当前进度
- `moon check --target all` 通过，`moon test` 为 43/43，通过 native release 构建。
- 官方 fixture：Good 85/112，Wrong 80/95，Suggestion Top-1 124/173。
- `PHONE`、`ph:`、`ph2`、`NGRAM` 主路径已通过，仓库提交记录和 CI 可公开审核。

## 八、交付范围
- 本次交付：可运行的纯 MoonBit Core、库 API、CLI、测试、兼容报告、README 和 Apache-2.0 许可证。
- 暂不承诺：100% Hunspell 兼容、所有非 UTF-8 编码、完整形态分析和全部语言音韵规则。

## 九、提交前补充
姓名：【待填写】；邮箱：【待填写】；微信/手机：【待填写】；团队成员：无；推荐人：【无/待填写】。