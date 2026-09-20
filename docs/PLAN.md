# MoonSpell：可执行改进方案 v2

> 项目名：MoonSpell  
> 定位：纯 MoonBit 实现的 Hunspell Core Compatible 拼写检查引擎  
> 参考版本：Hunspell v1.7.3  
> 参考实现：https://github.com/hunspell/hunspell  
> 格式规范：https://raw.githubusercontent.com/hunspell/hunspell/master/man/hunspell.5

## 零、最终兼容目标

MoonSpell 的最终目标是：**与 Hunspell v1.7.3 实现行为级兼容**，不以“能加载 en_US”冒充完全兼容。

只有当以下条件全部满足时，才允许对外声明 Full Compatibility：

1. Hunspell v1.7.3 官方测试集全部通过。
2. 官方测试中的 `.good`、`.wrong`、`.sug` 行为差异清零。
3. 对官方支持的 `.aff` directives 建立完整覆盖矩阵，无静默忽略。
4. 与 Hunspell 差分语料上的接受/拒绝结果一致。
5. 候选建议集合一致；若承诺完整行为兼容，则排序也必须一致。
6. 自定义随机差分测试在固定 seed 下无未解释偏差。
7. 记录并公开测试的 Hunspell 版本、词典、平台和失败项。

因此项目采用双目标：

- 当前截止日前：交付 MoonSpell Core，保证核心路径真实可用。
- 项目最终版本：持续收敛到 Hunspell v1.7.3 Full Compatible。
## 一、可行性结论

### 不可行的目标

不能在当前赛事周期内实现“完整 Hunspell 兼容”。原因：

- Hunspell 的 `affixmgr.cxx` 约 166 KB，建议模块 `suggestmgr.cxx` 约 75 KB，规则远不止简单前后缀。
- 官方测试目录约有 169 个 `.aff`、170 个 `.dic`、135 个 `.good`、115 个 `.wrong`、37 个 `.sug`。
- 复合词、continuation flags、双重后缀、建议排序、编码和形态分析彼此耦合。
- “兼容”如果没有量化标准和兼容矩阵，无法验收，也无法证明。

### 可行的目标

可以做出一个有真实价值的 MoonSpell Core：

- 纯 MoonBit，无 C FFI，不包装系统 Hunspell。
- 支持 UTF-8 和主流 flag 模式。
- 支持 PFX/SFX、条件、cross product、continuation flags。
- 支持核心复合词规则。
- 支持 REP、MAP、TRY、编辑距离和候选排序。
- 提供稳定库 API、CLI、结构化解释和 JSON 输出。
- 使用 Hunspell 官方 fixture 做差分测试，并自动生成兼容报告。

**判定：Core 版本可行，但必须按证据交付；Full Compatibility 不纳入承诺。**

## 二、产品定位

MoonSpell 不是 Hunspell 的逐行翻译，而是：

**A native MoonBit spelling engine with measurable Hunspell compatibility.**

核心竞争力：

1. 原生 MoonBit 实现，能够被 MoonBit 工具和应用直接复用。
2. 不只返回对错，还能解释“为什么接受”：
   - 精确命中；
   - 命中哪个 PFX/SFX；
   - 应用了哪些 continuation flags；
   - 复合词如何切分。
3. 不只说“兼容”，而是自动生成 directive 和 fixture 兼容矩阵。
4. 不支持的内容必须显式诊断，不能静默误判。

## 三、兼容级别

### P0：必须完成，不通过不能提交

- `.dic` 解析。
- `.aff` 解析：
  - `SET`
  - `FLAG char|long|num`
  - `AF` / `AM`
  - `PFX` / `SFX`
  - `NEEDAFFIX`
  - `FORBIDDENWORD`
  - `KEEPCASE`
  - `WORDCHARS`
  - `ICONV` / `OCONV`
  - `TRY`
  - `REP`
  - `MAP`
- UTF-8。
- 精确查询和大小写处理。
- 前后缀条件、strip/add、cross product。
- 词缀 continuation flags 和必要的双重后缀。
- 一次编辑候选建议。
- CLI：`check`、`suggest`、`explain`、`validate`。
- 严格返回带行号的解析错误。

### P1：尽力完成

- `COMPOUNDMIN`
- `COMPOUNDWORDMAX`
- `COMPOUNDFLAG`
- `COMPOUNDBEGIN` / `COMPOUNDMIDDLE` / `COMPOUNDEND`
- `COMPOUNDPERMITFLAG` / `COMPOUNDFORBIDFLAG`
- `ONLYINCOMPOUND`
- `CHECKCOMPOUNDDUP`
- `CHECKCOMPOUNDCASE`
- `CHECKCOMPOUNDTRIPLE`
- `CHECKCOMPOUNDREP`
- `COMPOUNDRULE` 的基础子集
- REP/MAP/TRY 联合排序。
- 二次编辑距离的受控候选生成。

### P2：明确延期

- 所有非 UTF-8 编码。
- 完整形态分析和 stem 输出。
- Hunspell 全部 CLI 交互模式。
- 所有语言的复杂音韵规则。
- 完整 Hungarian 复合词语义。
- 与 Hunspell 候选顺序逐项一致。
- 与 C++ 版本相同的性能指标。

## 四、量化验收标准

### 1. 构建与测试

- `moon check --target all` 通过。
- `moon test` 通过。
- GitHub Actions 在 Linux、macOS、Windows 至少覆盖两个平台。
- 无未处理 panic；坏词条、坏条件和不支持的 directive 都返回结构化错误。

### 2. 解析兼容

- 对官方测试文件逐个运行 `validate`。
- 支持范围内文件解析成功率：100%。
- 不支持 directive：100% 被识别并报告，不得静默忽略。
- 生成 `COMPATIBILITY.md`：
  - 文件；
  - 使用到的 directives；
  - 支持状态；
  - 跳过原因。

### 3. 接受/拒绝兼容

- `CoreSuite`：覆盖所有 P0 directives 的精选 fixture，必须 100% 通过。
- `OfficialSuite`：完整官方 fixture，生成真实通过率，不承诺首版 100%。
- 每个 `.good` 词必须接受，每个 `.wrong` 词必须拒绝。
- 任何失败必须能定位到 rule、候选 stem 或 compound split。

### 4. 建议兼容

- 对支持的 37 个 `.sug` fixture，目标候选进入 Top-10 的比例不低于 75%。
- 输出必须稳定、可复现。
- 不要求首版与 Hunspell 的排序完全一致。
- 每个建议附带来源：
  - `REP`
  - `MAP`
  - `TRY`
  - `EDIT`
  - `SPLIT`
  - `HYPHEN`

### 5. 性能

先测基线，再设门槛，不预先虚构数字。必须记录：

- 10 万 stem 词典加载时间。
- 10 万次精确查询吞吐。
- 10 万次词缀查询吞吐。
- 1000 次 suggestion 的 p50/p95/p99。
- 峰值内存。

硬性安全限制：

- suggestion 候选数必须有上限。
- 编辑距离、递归层次和 compound DP 状态必须有预算。
- 恶意超长词不能造成无界内存或递归。

## 五、对外 API

```text
load(aff_path, dic_path, options) -> Result<Dictionary, LoadError>
spell(dictionary, word) -> SpellResult
suggest(dictionary, word, limit) -> Array<Suggestion>
explain(dictionary, word) -> DecisionTrace
analyze(dictionary, word) -> AnalysisResult
validate(aff_path, dic_path) -> ValidationReport
```

`SpellResult`：

```text
accepted: Bool
reason: Exact | Affix | Compound | Forbidden | NeedAffix | NotFound
stem: String?
affixes: Array<AppliedAffix>
compound_parts: Array<String>
```

`DecisionTrace` 是差异化能力：说明词为什么被接受或被拒绝。建议放在首版核心 API 中，而不是后补。

CLI：

```text
moonspell check <file|-> --dict <path> --format text|json
moonspell suggest <word> --dict <path> --limit 10 --format text|json
moonspell explain <word> --dict <path>
moonspell validate --aff <path> --dic <path>
```

## 六、模块设计

```text
src/
  lib.mbt
  aff/
    lexer.mbt
    parser.mbt
    flags.mbt
    condition.mbt
    conversion.mbt
  dic/
    parser.mbt
    entry.mbt
  index/
    exact.mbt
    affix_index.mbt
    suffix_index.mbt
  engine/
    normalize.mbt
    case.mbt
    spell.mbt
    affix.mbt
    compound.mbt
    trace.mbt
  suggest/
    generator.mbt
    edit_distance.mbt
    replacer.mbt
    mapper.mbt
    ranking.mbt
  cli/
    main.mbt
testdata/
  core/
  upstream/
  malformed/
tools/
  conformance/
  differential/
bench/
```

## 七、核心算法决策

### 词典和索引

- `.dic` 流式读取，避免一次构造大量临时字符串。
- 维护 stem 精确索引。
- 维护 forbidden、needaffix、keepcase、compound 标记集合。
- 不做“全量展开所有派生词”的默认策略，避免词典膨胀。
- 通过前缀和尾部索引缩小 PFX/SFX 候选。

### 词缀还原

- 使用“候选规则 + stem 校验”，不是简单字符串删减。
- 条件表达式只实现 Hunspell 实际需要的字符类语义。
- 使用 visited state 防止 continuation flag 造成循环。
- cross product 和双重后缀必须保留完整应用路径。
- `NEEDAFFIX` 在最终接受前检查。
- 输出经 `OCONV`，输入先经 `ICONV`。

### 复合词

- 使用记忆化动态规划切分。
- 每个节点记录 BEGIN/MIDDLE/END 和 compound flags。
- `COMPOUNDMIN`、最大词数、重复和字符三重规则作为剪枝条件。
- 每个 compound split 都写入 trace。

### 建议生成

优先级：

1. REP 修复。
2. MAP 字符替换。
3. TRY 一次编辑。
4. 受限二次编辑。
5. compound split。
6. 空格和连字符候选。
7. 排序、去重、截断。

禁止的做法：全词典笛卡尔积、无上限递归、只按 Levenshtein 距离粗暴排序。

## 八、测试策略

### 单元测试

- 每种 directive 的正常和错误格式。
- char、long、num flag。
- condition、字符类、零字符 strip/add。
- cross product 和 continuation flags。
- NEEDAFFIX、FORBIDDENWORD、KEEPCASE。
- ICONV/OCONV round trip。
- compound DP。
- suggestion 顺序稳定性和去重。

### 官方 fixture 测试

- 跑 Hunspell 官方 `.aff/.dic/.good/.wrong/.sug`。
- 分为 P0、P1、Unsupported 三类。
- 输出 HTML、JSON、Markdown 三种报告。
- CI 只跑 CoreSuite；完整 OfficialSuite 在发布前运行。

### 差分测试

- 用系统 Hunspell v1.7.3 作为行为基准。
- 比较 token 接受/拒绝。
- 建议只比较目标候选是否进入 Top-K，不比较完整顺序。
- Hunspell 二进制只作为开发工具，不是 MoonSpell 运行时依赖。

### 模糊测试

- 随机生成合法和非法 `.aff` 行。
- 随机超长词、重复 flag、循环 continuation。
- 保证报错或返回，不崩溃、不挂死。

## 九、四天安全冲刺与止损线

假设单开发者全职、AI 辅助开发。

### 9 月 20 日：工程和 P0 上半

- 安装 MoonBit toolchain。
- 创建仓库、包、CI。
- 完成 `.dic` 和基础 `.aff` parser。
- 完成精确查询和 validate。
- 建立 fixture runner。
- 当天结束必须有可运行 CLI 和真实 commits。

**止损线：** parser 不通过，则不碰 compound，先保 CLI 和精确查询。

### 9 月 21 日：P0 词缀

- condition、PFX/SFX、cross product、continuation。
- NEEDAFFIX、FORBIDDENWORD、KEEPCASE。
- ICONV/OCONV。
- 完成 CoreSuite 第一版。
- `explain` 能输出命中规则。

**止损线：** cross product 未稳定，则只支持单层前缀或后缀，复合词降级为可选。

### 9 月 22 日：P1 与建议

- 基础 compound flags、MIN/MAX。
- REP、MAP、TRY。
- 一次编辑建议和稳定排序。
- JSON 输出。
- 开始跑 OfficialSuite。

**止损线：** suggestion 延迟失控，只保 REP/MAP/TRY，不做二次编辑。

### 9 月 23 日：收敛

- 修复测试中最高价值失败。
- benchmark、README、API 文档、兼容矩阵。
- mooncakes.io 预发布。
- 清理不支持 directive 的文档表述。

**止损线：** 只修 P0 和会误判的词，不再扩新 directive。

### 9 月 24 日：冻结提交

- 固定版本与测试报告。
- 确认公开仓库、CI、README、示例和许可证。
- 提交验收材料。

如果赛事群确认 9 月 30 日延期有效，9 月 25-30 日只做 P1 和兼容率提升。

## 九A、完全兼容路线图

### C0：MoonSpell Core

目标：在赛事截止日前形成可运行、可测试、可发布的核心版本。

- 核心 parser。
- 精确查询。
- PFX/SFX。
- 基础 compound。
- REP/MAP/TRY 和一次编辑建议。
- 官方 CoreSuite。
- CLI、JSON、README、CI、mooncakes 包。

### C1：规则语义收敛

目标：覆盖 `.aff` 的全部主流 directives 和 flag 语义。

- 完整 flag 模式。
- AF/AM 别名。
- continuation flags。
- 多重后缀和 prefix/suffix 依赖。
- CIRCUMFIX、KEEPCASE、NEEDAFFIX、FORBIDDENWORD。
- ICONV/OCONV、CHECKSHARPS、COMPLEXPREFIXES。
- 大小写、特殊字符、apostrophe 和 Unicode 规则。
- 非 UTF-8 编码策略。

### C2：复合词完全实现

目标：通过全部 compound fixture。

- COMPOUNDFLAG/BEGIN/MIDDLE/END。
- COMPOUNDPERMITFLAG/COMPOUNDFORBIDFLAG。
- ONLYINCOMPOUND、COMPOUNDROOT、COMPOUNDMORESUFFIXES。
- CHECKCOMPOUNDDUP/REP/CASE/TRIPLE。
- CHECKCOMPOUNDPATTERN。
- COMPOUNDRULE。
- COMPOUNDWORDMAX、COMPOUNDSYLLABLE、SYLLABLENUM。
- 语言特定 compound 边界。

### C3：建议行为收敛

目标：候选集合一致，最终达到顺序一致。

- TRY 的完整字符替换顺序。
- REP/MAP/PHONE。
- NGRAMSUGS、MAXNGRAMSUGS。
- MAXDIFF、ONLYMAXDIFF。
- split、dash、space、apostrophe 等候选。
- 大小写和 KEEPCASE 过滤。
- 相同候选去重和稳定排序。
- 与 Hunspell `.sug` 输出进行逐项差分。

### C4：全量兼容验证

目标：达到并证明 Full Compatibility。

- 全部官方 fixture 通过。
- 固定 seed 随机词差分。
- 多语言词典测试。
- 多平台 CI。
- 性能与内存基准。
- 兼容矩阵全部转为 supported。
- 对照 Hunspell v1.7.3 记录无已知行为偏差。

### 现实时间估算

- C0：约 4 天，前提是单开发者全职和 AI 辅助。
- C1-C4：约 4-8 周全职开发，复杂度取决于“候选顺序必须一致”和“所有语言必须一致”是否纳入定义。
- 如果要求直接移植 Hunspell C++ 算法，还要先审查 GPL/LGPL/MPL 许可及代码来源合规问题。

## 九B、完全兼容的开发纪律

1. 任何兼容声明必须绑定一个 fixture 列表。
2. 任何行为修复必须先添加最小回归用例。
3. 任何未支持 directive 都必须出现在兼容矩阵中。
4. 不因某个词典“看起来能用”就宣称兼容。
5. 不接受“结果差不多”，只接受可解释的差异或已登记差异。
6. 建议排序通过 `.sug` 差分后再宣称一致。
7. 每轮迭代记录 OfficialSuite 通过率，不允许无数据优化。
## 十、风险清单

| 风险 | 影响 | 对策 |
|---|---|---|
| 全兼容范围过大 | 项目失控 | P0/P1/P2 分级，禁止口头承诺全兼容 |
| Hunspell 语义复杂 | 误接受或误拒绝 | 固定 v1.7.3，用官方 fixture 差分 |
| 复合词规则复杂 | 大量边界错误 | 先支持核心 flags，COMPOUNDRULE 延期 |
| 建议质量不稳定 | 演示效果差 | 不承诺顺序，用 Top-K recall 度量 |
| UTF-8 外编码 | 加载错误 | 首版明确不支持，给出错误 |
| 测试数据许可证 | 发布风险 | 单独保留上游 notice，发布前审查 |
| MoonBit 工具链未安装 | 无法开工 | 第一项任务就是安装并跑通 hello world |
| 4 天时间不足 | 验收失败 | 9 月 24 日安全截止，所有扩展都是 stretch |

## 十一、评分层面的优势

相比普通“解析器 + 简单距离算法”，MoonSpell 更容易拿到工程质量分：

- 有明确的问题域和标准格式。
- 有官方差分基准。
- 有 parser、算法、数据结构、CLI、测试多个可展示模块。
- `explain` 输出能直观展示复杂词缀和复合词决策。
- 兼容矩阵可以量化进展，而不是展示截图。
- 纯 MoonBit 实现具有生态复用价值。

## 十二、最终承诺边界

可以对外说：

> MoonSpell is a pure-MoonBit Hunspell-compatible spelling engine. It supports a documented core subset of the Hunspell `.aff/.dic` format, including affix checking, core compound rules and ranked suggestions. Compatibility is measured against Hunspell v1.7.3 fixtures.

不能说：

> MoonSpell is fully compatible with Hunspell.

只有全部官方 fixture 通过，并且行为差分全部收敛后，才允许改成 full compatibility。



