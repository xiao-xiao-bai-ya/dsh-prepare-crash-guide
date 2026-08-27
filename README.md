# DSH 急救手册：工具全部失灵，报「Cannot read properties of undefined (reading 'prepare')」

> **给谁看**：完全没写过代码的 DSH 用户。你只需要会两个动作——打开 PowerShell 窗口、复制粘贴命令。
> **适用版本**：DSH 0.1.0-rc.6 及相近版本（官方修复发布前，本手册方法持续有效）。
> **阅读时间**：全文约 10 分钟；急着修好直接跳到「第一步：确认问题」。

---

## 目录

1. [这是什么病](#1-这是什么病)
2. [30 秒自测：你是不是中招了](#2-30-秒自测你是不是中招了)
3. [先认识 3 个词](#3-先认识-3-个词)
4. [坏掉的真正原因（大白话版）](#4-坏掉的真正原因大白话版)
5. [哪些操作会触发](#5-哪些操作会触发)
6. [第一步：确认问题（1 分钟）](#6-第一步确认问题1-分钟)
7. [修复：四步走，做完一步验一步](#7-修复四步走做完一步验一步)
8. [为什么出事的旧会话救不回来](#8-为什么出事的旧会话救不回来)
9. [预防：以后装插件前的 30 秒体检](#9-预防以后装插件前的-30-秒体检)
10. [常见问题 FAQ](#10-常见问题-faq)
11. [术语表](#11-术语表)
12. [资料来源](#12-资料来源)

---

## 1. 这是什么病

用着用着，DSH 里的 AI 突然「瘫痪」了，典型画面：

- 每一次工具调用都失败，界面上出现红字：

  > 本轮运行失败 Cannot read properties of undefined (reading 'prepare')

- 错误标记是 `UNKNOW`
- 不是某一个工具坏，而是**所有工具一起坏**：执行命令、读写文件、搜索，全都一样失败
- 问它「为什么失败」，它连解释问题用的工具都调不动
- 重启 DSH 后，**新**会话可能恢复正常，但出事的那个**旧**会话永远修不好（原因见[第 8 节](#8-为什么出事的旧会话救不回来)）

**这不是你操作错了，也不是网络断了。** 这是 DSH 当前版本一个已知的高发 bug：某个核心组件被意外复制成了两份，导致工具调度系统「认不出」自己的工具。官方还没发布修复，但社区已经把根因查到了源码级别，修复方法也验证过很多次了——照着本手册做就能解决。

---

## 2. 30 秒自测：你是不是中招了

下面几条，符合得越多，越是这个病：

| # | 症状 | 符合？ |
|---|------|--------|
| 1 | 报错信息里含 `reading 'prepare'` | ☐ |
| 2 | 失败的是**所有**工具，不是某一个 | ☐ |
| 3 | 出事前刚装过插件，或刚更新/重装过 DSH | ☐ |
| 4 | 反复重试、重开会话都没用 | ☐ |
| 5 | 重启 DSH 后旧会话仍然全挂，甚至整个会话直接被拒绝 | ☐ |

中招了？往下看。一条都不符合？那你的问题可能不在这里（但读读第 4 节也不亏，能搞懂 DSH 是怎么工作的）。

---

## 3. 先认识 3 个词

理解这个 bug 只需要 3 个词，30 秒：

| 词 | 大白话解释 |
|------|------|
| **profile** | DSH 的「配件柜」。你最常用的那个大概叫 `web`，位置在 `C:\Users\你的用户名\.dsh\profiles\web\`。你装的插件都放在这个柜子里 |
| **插件（plugin）** | 给 DSH 增加功能的小配件，比如「让 AI 能看图」「给界面加侧边栏」 |
| **node_modules** | 配件柜里的「零件仓库」文件夹。插件和它依赖的零件都放这里 |

还有一组关键对比，请务必分清：

- **软链（快捷方式）**：文件夹里放的不是真东西，而是一个「指针」，指向真正的官方安装。**这是正常状态**——全机器只有一份核心组件，大家共用。
- **实体文件夹**：零件被完完整整**复制了一份**进来。**这就是祸根。**

在 Windows 上查看一个文件夹是不是快捷方式，看它的 `LinkType` 属性：有值（如 `Junction`）就是快捷方式，空白就是实体文件夹。本手册的检查命令就是在看这个。

---

## 4. 坏掉的真正原因（大白话版）

### 一句话版本

> **登记工具时用的是 A 复制品的印章，查找工具时拿的是 B 复制品的印章去比对——纹路永远对不上，于是什么都查不到，程序当场崩溃。**

### 展开讲

DSH 内部给工具「盖章登记」「验章查找」时，用了一种叫 **Symbol** 的特殊标识。Symbol 有个脾气：**每次铸造都独一无二**。就像防伪印章，哪怕两枚章上刻着一模一样的字，章面纹路也完全不同。

出问题的代码在 `@deepseek-ai/dsh-agent-loop` 里，就一行：

```js
const prepared = await ctx.tools[TOOL_RUNTIME_SCHEDULER].prepare(call.exec);
```

这行的意思是：「拿着印章 `TOOL_RUNTIME_SCHEDULER` 去工具箱里找到调度器，然后准备执行这次调用」。

正常情况：整台电脑只有 **1 份**核心组件。登记和查找用的是**同一枚章**，一盖就对上。

出事情况：某个插件把核心组件**复制了第二份**（术语叫「实体化」）。于是：

1. DSH 启动时，工具登记用的是 **A 份**现场刻的章
2. 每次调用工具时，查找用的是 **B 份**现场刻的章
3. 两枚章纹路不同 → 查到的结果是「空」（`undefined`）
4. 程序继续去拿空东西的 `.prepare` → 当场崩溃

**为什么所有工具一起挂？** 因为不管调用哪个工具，都要过「查找调度器」这一道关卡。关卡塌了，路路不通。

**为什么版本一样也不行？** 因为章是「每次铸造现场刻」的，跟版本号没有任何关系。两份组件哪怕版本号完全相同，刻出来的章也不相等。

---

## 5. 哪些操作会触发

| 场景 | 发生了什么 | 常见程度 |
|------|------|------|
| **插件自带核心包依赖** | 插件作者把 `@deepseek-ai/dsh-tools`（或 `@deepseek-ai/cordis`、`@deepseek-ai/dsh-subprocess`、`@deepseek-ai/dsh-commands`）写进了自己插件的 `dependencies`。安装插件时，包管理器会「贴心地」把这些核心包复制一份实体进 profile——灾难开始 | ⭐ 最常见 |
| **在 profile 目录里手动跑过 `pnpm install`** | 同样会把核心包实体化到 profile 本地 | 常见 |
| **npm 全局版和 DSH Desktop 共用同一个 `$DSH_HOME`** | 两套安装抢同一个 profile，软链指向错乱（对应社区 issue #227 的场景） | 相对少见 |
| **版本错位（如 rc.5 和 rc.6 混装）** | 也会造成两个运行时并存 | 少见 |

如果你最近「装了一批社区插件之后突然全挂」，基本就是第一种场景。

---

## 6. 第一步：确认问题（1 分钟）

### 方法一：一条命令（推荐先做这个）

1. 按键盘上的 `Win` 键，输入 `powershell`
2. 回车，打开一个蓝色（或黑色）的命令窗口
3. 把下面这段**整段复制**，粘贴进窗口，按回车：

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\profiles\web\node_modules\@deepseek-ai" -ErrorAction SilentlyContinue | Select-Object Name, LinkType, LinkTarget
```

4. 看输出：

| 输出 | 判断 |
|------|------|
| 什么都不显示，或所有行的 `LinkType` 都是 `Junction` / `SymbolicLink` | 这层没问题（继续看「痊愈判据」检查另一层） |
| 出现了 `LinkType` 空白的行，尤其是名字叫 `dsh-tools`、`cordis`、`dsh-subprocess`、`dsh-commands` | **就是它了**，进入第 7 节修复 |

### 方法二：一键体检脚本（懒人版）

本仓库附带 `check_dual_copy.ps1`，把上面的判断逻辑自动化了，还会顺带检查另外两层。用法：

1. 把 `check_dual_copy.ps1` 下载到桌面
2. 打开 PowerShell，粘贴这一行并回车（文件名按实际位置改）：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\check_dual_copy.ps1"
```

3. 看最后的「体检结论」。脚本**只读不改**，放心运行。

---

## 7. 修复：四步走，做完一步验一步

> 原则：从「便宜」到「贵」依次尝试。多数人做完第 1、2 步就好了。
> 所有命令都可以直接复制粘贴。

### 第 1 步：卸掉嫌疑插件

最近装了哪个插件，就从哪个开始卸：

```powershell
dsh plugin --profile web remove 插件名
```

- 一次卸一个，卸一个验一次（验证方法见「痊愈判据」）
- 不记得装过什么？先跑这个看清单：

```powershell
dsh plugin --profile web list
```

### 第 2 步：删掉被污染的零件仓库

卸了插件，被复制进来的文件可能还留着。整个删掉，不用担心——里面都是副本，DSH 下次启动会自动按需重建：

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\profiles\web\node_modules"
```

### 第 3 步：清掉「卡自愈」的空目录（最容易被忽略的一步）

DSH 有自愈机制：发现零件仓库缺东西时会自动补软链。但如果存在一个**不是快捷方式的空目录**，自愈逻辑会被它卡住，怎么重启都修不好。实战中抓到一个惯犯叫 `html-void-elements`：

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\profiles\node_modules\html-void-elements"
```

> 如果提示找不到路径，说明本来就没有，跳过即可。

### 第 4 步：重启 + 换新会话验证

1. **完全关闭** DSH（确认没有残留进程）
2. 重新启动 DSH（例如 `dsh web`）
3. **新建一个会话**来测试工具是否恢复

> 为什么必须换新会话？因为出事的旧会话日志已经损坏，救不回来了。见下一节。

### 痊愈判据（修完必查，两条都过才算好）

```powershell
# 判据 1：这里应该是空的，或者全是 Junction/SymbolicLink（不能有 LinkType 空白的实体目录）
Get-ChildItem "$env:USERPROFILE\.dsh\profiles\web\node_modules\@deepseek-ai" -ErrorAction SilentlyContinue | Select-Object Name, LinkType

# 判据 2：这里的核心包应该是 Junction，LinkTarget 指向 npm 全局安装目录
Get-ChildItem "$env:USERPROFILE\.dsh\profiles\node_modules\@deepseek-ai" -ErrorAction SilentlyContinue | Select-Object Name, LinkType, LinkTarget
```

两条判据通过 + 新会话里工具能正常跑 = **修好了**。

---

## 8. 为什么出事的旧会话救不回来

崩溃发生的时机非常刁钻：在「我要调用工具」写进日志**之后**、「工具结果写回日志」**之前**。

于是这个会话的日志（`session.jsonl`）里出现了一笔烂账：

- 记了账：「我要调用工具 × N」
- 少了账：这 N 个调用的结果

之后你每次打开这个旧会话，AI 服务端一对账就拒收，报错类似：

> An assistant message with 'tool_calls' must be followed by tool messages responding to each 'tool_call_id' (insufficient tool messages following tool_calls message)

这是**账本物理性损坏**，跟双副本 bug 修没修好无关——bug 修好只能保证**新**会话正常。旧会话里的文字内容还能复制出来留档，但会话本身放弃吧，新建一个。

---

## 9. 预防：以后装插件前的 30 秒体检

### 装之前：查依赖（最重要的一步）

把命令里的「包名」换成你要装的插件包名：

```powershell
npm view 包名 dependencies --json
```

看输出：只要出现下面**任何一个**，就要警惕：

- `@deepseek-ai/dsh-tools`
- `@deepseek-ai/cordis`
- `@deepseek-ai/dsh-subprocess`
- `@deepseek-ai/dsh-commands`

处理方式：最好不装；实在想装，装完立刻按第 7 节清理一次。

### 装之后：查一眼 LinkType

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\profiles\web\node_modules" -ErrorAction SilentlyContinue | Select-Object Name, LinkType
```

出现 `LinkType` 空白的实体核心包 = 又复制了，回第 7 节处理。

### 四条铁律

1. **永远不要**在 profile 目录里手动执行 `pnpm install`
2. **不要**让 DSH Desktop 和 npm 全局版共用同一个 `$DSH_HOME`
3. **不要**指望 `pnpm overrides` 锁版本能解决问题——它只锁版本号，**不移除实体副本**，实测无效
4. 遇到「自带核心包」的插件，去插件仓库提个 issue，请作者把核心包从 `dependencies` 挪到 `peerDependencies`（意思是「主程序自带了，别帮我复制」），一劳永逸

---

## 10. 常见问题 FAQ

**Q：重启电脑有用吗？**
A：没用。多出来的那份文件还躺在硬盘上，开机照崩。

**Q：把插件升级到最新版有用吗？**
A：没用。这个病与版本无关，只与「核心组件有几份实体」有关。

**Q：为什么我卸了插件还是崩？**
A：卸载通常不会删干净已复制进来的文件。继续做第 2、3 步。

**Q：删 node_modules 会丢我的配置吗？**
A：不会。你的配置、会话记录都不在 node_modules 里；那里只放可重建的代码副本。

**Q：官方会修吗？**
A：该问题在 0.1.0-rc.6 属已知高发问题，社区已定位到源码级。官方修复发布前，本手册的手动方法就是主要手段。

**Q：我不是 `web` profile 怎么办？**
A：把命令里的 `web` 换成你的 profile 名即可（用 `dsh plugin --profile 你的profile名 list` 确认名字）。

---

## 11. 术语表

| 术语 | 意思 |
|------|------|
| Symbol | JavaScript 语言里的一种特殊标识符，**每次生成都独一无二**，常用来当「唯一钥匙」 |
| 软链 / Junction / SymbolicLink | 文件系统层面的「快捷方式」，本身不占实体空间，指向真身 |
| 实体化 | 原本应该是快捷方式的目录，变成了完整拷贝 |
| node_modules | 包管理器存放代码包及其依赖的仓库目录 |
| pnpm / npm | 包管理器，负责安装、管理插件和依赖 |
| dependencies | 插件声明「我依赖这些包，请帮我安装（复制）」的清单 |
| peerDependencies | 插件声明「我依赖这些包，但主程序自带了，**别复制**，共用就行」的清单 |
| `$DSH_HOME` | DSH 的主数据目录，默认在 `C:\Users\你的用户名\.dsh` |
| API 400 | 服务端认为请求内容不合法而拒绝处理，本文里特指会话日志烂账导致的拒收 |

---

## 12. 资料来源

1. **社区源码级分析**（dshdocs.com 等社区整理，「双副本 Symbol 失配」根因与修复路径；来源由用户提供，未逐条独立核实）
2. **DSH 社区 issue #227**（npm 全局版与 DSH Desktop 共用 `$DSH_HOME` 引发双运行时的场景）
3. **一线实战记录**（2026-08：症状识别 → 手动四步修复 → 痊愈判据 → 预防清单，含 `html-void-elements` 空目录卡自愈的发现，均经实机验证）

---

> **一句话总结**：所有工具同时报 `prepare` 崩溃 = 核心组件被复制了两份。卸嫌疑插件 → 删 profile 的 `node_modules` → 删 `html-void-elements` 空目录 → 重启换新会话。以后装插件前，先 `npm view 包名 dependencies --json` 查一眼。
