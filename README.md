# DSH 修复教程：所有工具调用失败，报错 Cannot read properties of undefined (reading 'prepare')

> **给谁看**：没有编程基础、不了解 DSH 内部结构的用户。
> **你需要的全部技能**：会打开 PowerShell 窗口、会复制粘贴文字。
> **适用版本**：DSH 0.1.0-rc.6 及相近版本。官方修复发布前，本教程的手动方法持续有效。
> **本教程的写法**：先补充前置知识，再讲执行流程，然后逐行解释每一行代码和命令，每处都说明为什么这么写，最后按步骤总结完整数据流。不使用比喻，直接讲技术概念。

---

## 目录

1. [这份教程解决什么问题](#1-这份教程解决什么问题)
2. [前置知识：开始前先弄懂 6 个概念](#2-前置知识开始前先弄懂-6-个概念)
3. [DSH 执行一次工具调用的完整流程](#3-dsh-执行一次工具调用的完整流程)
4. [崩溃代码逐段解释](#4-崩溃代码逐段解释)
5. [为什么会出现两份核心代码](#5-为什么会出现两份核心代码)
6. [第一步：确认问题](#6-第一步确认问题)
7. [修复：四步](#7-修复四步)
8. [为什么出事的旧会话救不回来](#8-为什么出事的旧会话救不回来)
9. [预防：装插件前的检查](#9-预防装插件前的检查)
10. [常见问题 FAQ](#10-常见问题-faq)
11. [完整数据流总结：修复前与修复后](#11-完整数据流总结修复前与修复后)
12. [术语表](#12-术语表)
13. [资料来源](#13-资料来源)
14. [哪一节还没看懂](#14-哪一节还没看懂)
15. [附录 A：check_dual_copy.ps1 脚本讲解](#附录-acheck_dual_copyps1-脚本讲解)

---

## 1. 这份教程解决什么问题

使用 DSH 时突然出现以下情况：

- 每一次工具调用都失败，界面显示：

  > 本轮运行失败 Cannot read properties of undefined (reading 'prepare')

- 错误标记是 `UNKNOW`
- 不是某一个工具失败，而是**所有工具全部失败**：执行命令、读写文件、搜索，结果相同
- 重启 DSH 后，新建的会话可能恢复正常，但出事的那个旧会话永远无法恢复（原因见第 8 节）

**原因结论**：这不是操作错误，也不是网络问题。是 DSH 当前的已知缺陷：某个核心代码包被意外复制成两份，导致工具调度系统查找不到自己的工具。官方尚未发布修复，本教程给出经过验证的手动修复步骤。

症状核对表（符合越多，越是这个问题）：

| # | 症状 | 符合 |
|---|------|------|
| 1 | 报错信息含 `reading 'prepare'` | ☐ |
| 2 | 失败的是所有工具，不是某一个 | ☐ |
| 3 | 出事前刚装过插件，或刚更新/重装过 DSH | ☐ |
| 4 | 反复重试、重开会话都无效 | ☐ |
| 5 | 重启后旧会话仍然全部失败，或整个会话被服务端拒绝 | ☐ |

---

## 2. 前置知识：开始前先弄懂 6 个概念

后面所有解释都会用到这 6 个概念。如果某个你已经懂，直接跳过。

### 2.1 路径与环境变量

- **路径**：文件或文件夹在磁盘上的位置，例如 `C:\Users\ww\.dsh\profiles\web`。反斜杠 `\` 是 Windows 路径的分隔符。
- **环境变量**：操作系统保存的设置值，任何程序都能读取。`USERPROFILE` 是其中一个，值是当前用户的主目录，例如 `C:\Users\ww`。
- **`$env:USERPROFILE`**：在 PowerShell 中读取环境变量的固定写法，格式是 `$env:` 加变量名。所以 `"$env:USERPROFILE\.dsh"` 展开后就是 `C:\Users\ww\.dsh`。
- **为什么这么写**：不把 `C:\Users\ww` 写死在命令里，换一台电脑、换一个用户名，同一条命令依然正确。

### 2.2 node_modules 与依赖包

- DSH 和它的插件都用 JavaScript/TypeScript 编写，运行在 Node.js 上。
- Node.js 的代码按**包（package）**组织：一个包是一个功能单元，对应一个文件夹，文件夹内有清单文件 `package.json`，记录包的名称、版本、依赖。
- **`node_modules`** 是固定名称的目录，专门存放这些包。代码里写 `import ... from '包名'` 时，Node 按固定规则到 node_modules 里查找对应文件夹。
- **依赖会套依赖**：A 包声明需要 B 包，B 又声明需要 C。安装 A 时，包管理器会把 B 和 C 一起装进 node_modules。
- DSH 的核心代码同样是包，名称以 `@deepseek-ai/` 开头（组织名前缀），例如：
  - `@deepseek-ai/dsh-tools`：工具运行时与调度
  - `@deepseek-ai/cordis`：插件框架
  - `@deepseek-ai/dsh-subprocess`：子进程管理
  - `@deepseek-ai/dsh-commands`：命令相关
- 本教程的核心结论提前给出：**这些核心包在全机器上只能存在一份**。出现两份实体，就会触发本教程要修的故障。

### 2.3 软链与实体目录

- **实体目录**：磁盘上真实存放文件的文件夹。
- **软链**：目录本身不存放文件，只存放一个指向另一个位置的引用。Windows 上常见两种形式：`Junction`（目录联接）和 `SymbolicLink`（符号链接）。资源管理器里的「快捷方式」是同类思想的图形化实现，但软链工作在文件系统层面，程序访问软链与访问真实目录几乎无区别。
- **如何区分**：查看条目的 `LinkType` 属性。有值（`Junction` 或 `SymbolicLink`）= 软链；空白 = 实体目录。
- **DSH 的正常设计**：profile 目录下的核心包以软链形式指向唯一一份正式安装。效果是全机器只有一份核心代码，所有程序共用同一个实例。

### 2.4 插件是怎么装进 DSH 的

1. 执行 `dsh plugin --profile web add 插件名`，或在 DSH 内触发安装。
2. DSH 调用包管理器 pnpm 下载插件。
3. pnpm 读取插件 `package.json` 里的 `dependencies` 字段（插件在此声明：安装我时，请把这些包也一并装上）。
4. pnpm 把插件和它声明的依赖一起写入 `profiles\web\node_modules`。
5. **故障入口在第 4 步**：如果依赖清单里包含 DSH 核心包，pnpm 会在 profile 里再放一份核心包的实体副本。于是全机器出现了两份核心代码。

### 2.5 Symbol

- Symbol 是 JavaScript 的一种原始数据类型（与数字、字符串、布尔值并列）。
- 生成方式：`Symbol()` 或 `Symbol('描述文字')`。
- **核心特性：每次调用返回一个全新的、唯一的值。** 两次调用即使传入完全相同的描述文字，得到的两个 Symbol 也不相等。描述文字只用于调试显示，不参与相等性比较。
- 验证方法：在浏览器按 `F12` 打开开发者工具，切到 Console（控制台），输入：

  ```js
  Symbol('a') === Symbol('a')   // 输出 false
  ```

  `===` 是 JavaScript 的严格相等比较。输出 false 说明两个 Symbol 不相等。
- **用途**：作为对象的键。写入和读取必须使用同一个 Symbol 值才能命中。
- **副作用**：写入时用的 Symbol 和读取时用的 Symbol 如果不是同一次调用产生的，读取结果就是 `undefined`（表示“这个键不存在”），并且**不报错**。后续代码如果在 undefined 上继续取属性，就会抛出错误——这正是本教程的报错来源。

### 2.6 打开并使用 PowerShell

1. 按键盘 `Win` 键。
2. 直接输入 `powershell`。
3. 回车，出现蓝底或黑底窗口。
4. 粘贴：在窗口内单击鼠标右键，或按 `Ctrl+V`。回车执行。

---

## 3. DSH 执行一次工具调用的完整流程

以「用户要求 AI 执行一条 PowerShell 命令」为例。正常情况共 9 步：

| 步骤 | 发生什么 | 涉及的组件 |
|------|----------|------------|
| 1 | 用户在输入框发送消息 | DSH 网页界面 |
| 2 | DSH 把会话历史发送给 AI 服务 | DSH 会话模块 |
| 3 | AI 返回内容中包含 `tool_calls` 字段，表示「我要调用某个工具」 | AI 服务 |
| 4 | DSH 的执行循环模块 agent-loop 逐条取出 tool_calls | `@deepseek-ai/dsh-agent-loop` |
| 5 | agent-loop 用 Symbol 键在 ctx.tools 对象中查找「工具调度器」服务 | `@deepseek-ai/dsh-tools` |
| 6 | 调用调度器的 prepare 方法：查找工具定义、校验参数、准备执行环境 | `@deepseek-ai/dsh-tools` |
| 7 | 真正执行工具（例如启动 PowerShell 执行命令），取得输出 | 各工具模块 |
| 8 | 把「发起了什么调用、结果是什么」成对写入会话日志 session.jsonl | 会话存储 |
| 9 | 把工具结果发回 AI，AI 生成下一轮回答 | AI 服务 |

**故障位置**：第 5 步查不到调度器（返回 undefined），第 6 步在 undefined 上取 `.prepare` 属性，程序抛出：

> Cannot read properties of undefined (reading 'prepare')

含义：`无法从不存在的值（undefined）上读取 'prepare' 属性`。

**两个连锁后果**：

- 第 7、8 步没有执行：日志里只有「发起了调用」（tool/call）的记录，缺少配对的「调用结果」（tool/result）。这直接导致第 8 节「旧会话无法恢复」。
- 所有工具一起失败：第 5 步是所有工具调用的公共必经步骤，这一步失败，任何工具都到不了第 7 步。

---

## 4. 崩溃代码逐段解释

出错的代码在 `@deepseek-ai/dsh-agent-loop` 包中，只有一行：

```js
const prepared = await ctx.tools[TOOL_RUNTIME_SCHEDULER].prepare(call.exec);
```

逐段解释：

| 代码片段 | 语法类型 | 作用 |
|----------|----------|------|
| `const` | 声明关键字 | 声明一个变量，且声明后不能重新赋值 |
| `prepared` | 变量名 | 保存 prepare 的返回值，供后续执行阶段使用 |
| `await` | 运算符 | 等待异步操作完成并取出结果；表示「等 prepare 执行完毕再继续」 |
| `ctx` | 变量 | 当前运行环境的上下文对象，各类服务都挂载在它上面 |
| `.tools` | 属性访问 | 取 ctx 的 tools 属性，这是一个存放工具运行时服务的注册表对象 |
| `[TOOL_RUNTIME_SCHEDULER]` | 方括号按键取值 | 键不是字符串，而是一个 Symbol 值（含义见下） |
| `.prepare` | 属性访问 | 取出调度器对象上的 prepare 方法 |
| `(call.exec)` | 函数实参 | call.exec 是本次调用的执行信息（工具名、参数），作为输入传给 prepare |
| `;` | 标点 | 语句结束符 |

其中 `TOOL_RUNTIME_SCHEDULER` 在 `@deepseek-ai/dsh-tools` 包中的定义是：

```js
const TOOL_RUNTIME_SCHEDULER = Symbol('@deepseek-ai/dsh-tools.scheduler');
```

- `Symbol('@deepseek-ai/dsh-tools.scheduler')`：生成一个唯一值，括号里的字符串只是描述文字。
- 整行含义：生成一个 Symbol，存进常量 TOOL_RUNTIME_SCHEDULER。
- 任何代码想从 ctx.tools 里取到调度器，必须使用**同一个常量导出的同一个 Symbol 值**。

### 为什么这么设计

1. **为什么用 Symbol 当键，不用字符串？**
   DSH 是插件架构，许多模块都会向 ctx 挂载服务。如果用字符串做键，两个模块可能使用同一个字符串，后挂载的覆盖先挂载的，产生难以排查的错误。Symbol 每次生成都唯一：只有共享同一个 Symbol 实例的代码才能访问对应服务。这是用语言机制保证的隔离性。
2. **为什么先 prepare 再执行？**
   查找工具定义、校验参数、标准化请求，是所有工具通用的前置流程。抽成一个公共的 prepare 入口，所有工具走同一条路径，这段逻辑只需要写一次。好处是一致性好、维护点单一。
3. **这套设计的前提**
   登记服务和查找服务必须使用同一个 Symbol 值，等价于：**全机器只能有一份 `@deepseek-ai/dsh-tools`**。

### 崩溃的精确过程

1. 正常状态：profile 里的核心包是软链，指向唯一安装。登记服务的代码和 agent-loop 加载的是**同一份** `@deepseek-ai/dsh-tools`，使用同一个 Symbol 值。第 5 步查找成功。
2. 双副本状态：profile 里出现了第二份实体的 `@deepseek-ai/dsh-tools`。Node.js 解析 import 时采用就近原则（从当前文件所在目录逐级向上找 node_modules，找到最近的就用），于是 agent-loop 实际加载到本地实体副本。此时：
   - 登记服务时，某份代码用 A 副本里的 Symbol 值作为键写入了注册表；
   - 查找服务时，agent-loop 用 B 副本里的 Symbol 值去查。
   - 两个 Symbol 值不相等（描述文字相同也不相等）→ 查找返回 undefined。
3. 第 6 步在 undefined 上访问 `.prepare`，抛出 TypeError，本轮工具调用失败。
4. **与版本号无关**：Symbol 的唯一性是 JavaScript 语言规则。两份代码即使版本完全相同，两次 `Symbol()` 的结果也不相等。

---

## 5. 为什么会出现两份核心代码

| 场景 | 具体过程 | 常见程度 |
|------|----------|----------|
| 插件把核心包写进 `dependencies` | 安装插件时 pnpm 按 `dependencies` 清单把核心包复制进 profile。只要清单里有 `@deepseek-ai/dsh-tools`、`@deepseek-ai/cordis`、`@deepseek-ai/dsh-subprocess`、`@deepseek-ai/dsh-commands` 之一，就会产生第二份 | 最常见 |
| 在 profile 目录里手动执行过 `pnpm install` | 同样会把核心包实体化到 profile 本地 | 常见 |
| npm 全局版与 DSH Desktop 共用 `$DSH_HOME` | 两个运行时争用同一个 profile，软链指向错乱（对应社区 issue #227 的场景） | 相对少见 |
| 版本错位（例如 rc.5 与 rc.6 混装） | 同样形成两个运行时并存 | 少见 |

> `$DSH_HOME` 是 DSH 的主数据目录，默认位置 `C:\Users\用户名\.dsh`。
> 如果你最近「装了一批社区插件之后全部工具失败」，大概率是第一种场景。

---

## 6. 第一步：确认问题

### 方法一：一条命令

打开 PowerShell（方法见 2.6），粘贴以下命令并回车：

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\profiles\web\node_modules\@deepseek-ai" -ErrorAction SilentlyContinue | Select-Object Name, LinkType, LinkTarget
```

逐段解释（单行命令，从左到右拆开）：

| 片段 | 作用 |
|------|------|
| `Get-ChildItem` | PowerShell 内置命令：列出目录下的条目（子目录、文件） |
| `"$env:USERPROFILE\.dsh\profiles\web\node_modules\@deepseek-ai"` | 第一个参数：要列出的目录路径。`$env:USERPROFILE` 在执行时替换为你的用户主目录 |
| `-ErrorAction SilentlyContinue` | 参数：目录不存在时不显示错误、不中断，直接静默跳过（SilentlyContinue = 静默继续） |
| `\|` | 管道符：把左边命令的输出交给右边命令继续处理 |
| `Select-Object Name, LinkType, LinkTarget` | 从每个条目中只显示 3 个属性：Name 名称、LinkType 链接类型、LinkTarget 链接指向 |

结果判读：

| 输出 | 结论 |
|------|------|
| 无输出，或所有条目的 LinkType 都是 `Junction` / `SymbolicLink` | 这一层正常，再执行「痊愈判据」检查另一层（见第 7 节末尾） |
| 出现 LinkType 空白的条目，尤其是 `dsh-tools`、`cordis`、`dsh-subprocess`、`dsh-commands` | 确认存在双副本，进入第 7 节修复 |

### 方法二：一键体检脚本

使用本仓库的 `check_dual_copy.ps1`（脚本逐段讲解见附录 A）：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\ww\Desktop\check_dual_copy.ps1"
```

| 片段 | 作用 |
|------|------|
| `powershell` | 启动一个新的 PowerShell 进程来执行脚本 |
| `-ExecutionPolicy Bypass` | 仅本次运行放行脚本执行。Windows 默认禁止直接运行 .ps1 脚本文件，此参数只对本次生效，不修改系统设置 |
| `-File "路径"` | 指定要运行的脚本文件路径（按你实际保存的位置修改） |

脚本只读取信息，不修改任何文件，可以放心运行。运行后看最后的「体检结论」。

---

## 7. 修复：四步

按顺序执行，每步做完做一次验证。多数情况完成第 1、2 步即可恢复。

### 第 1 步：卸载可疑插件

```powershell
dsh plugin --profile web remove 插件名
```

| 片段 | 作用 |
|------|------|
| `dsh` | DSH 的命令行程序 |
| `plugin` | 子命令：插件管理 |
| `--profile web` | 选项：指定操作 web 这一层 profile。如果你的 profile 名称不是 web，替换为实际名称 |
| `remove 插件名` | 动作：卸载指定插件 |

不确定装过哪些插件时，先列清单：

```powershell
dsh plugin --profile web list
```

（`list` = 列出全部已装插件。）

操作方式：一次卸载一个，每卸一个就用第 6 节的命令检查一次。优先卸载最近安装的。

### 第 2 步：删除被污染的 node_modules

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\profiles\web\node_modules"
```

| 片段 | 作用 |
|------|------|
| `Remove-Item` | PowerShell 内置命令：删除条目 |
| `-Recurse` | 递归删除：连同全部子目录和文件一起删除 |
| `-Force` | 强制删除：不逐项询问确认，允许删除隐藏和只读条目 |
| `"..."` | 要删除的目录路径 |

**为什么可以放心删**：node_modules 里的内容全部是可重新获取的代码副本，不包含你的配置和会话记录。DSH 启动时的自愈机制会按需重建，并把核心包重新以软链形式接回唯一安装。

### 第 3 步：删除卡住自愈的空目录

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.dsh\profiles\node_modules\html-void-elements"
```

各片段含义与第 2 步相同。

**为什么需要这一步**：DSH 的自愈机制在重建软链时，如果目标位置已经存在一个真实目录（哪怕里面是空的），软链创建会失败或被跳过，自愈流程无法完成。实测中发现 `html-void-elements` 曾以非软链空目录的形式存在，卡住了整个自愈过程。如果命令提示找不到该路径，说明本机没有此问题，跳过即可。

### 第 4 步：重启 DSH 并新建会话验证

1. 完全关闭 DSH，确认没有残留进程。
2. 重新启动 DSH。
3. **新建一个会话**测试工具是否恢复。不要使用出事的旧会话，原因见第 8 节。

### 痊愈判据（修复后必查）

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\profiles\web\node_modules\@deepseek-ai" -ErrorAction SilentlyContinue | Select-Object Name, LinkType
```

期望结果：无输出，或全部条目 LinkType 有值（Junction/SymbolicLink）。

```powershell
Get-ChildItem "$env:USERPROFILE\.dsh\profiles\node_modules\@deepseek-ai" -ErrorAction SilentlyContinue | Select-Object Name, LinkType, LinkTarget
```

期望结果：核心包条目的 LinkType 为 `Junction`，LinkTarget 指向 npm 全局安装目录。

两条判据都通过，并且新会话里工具能正常执行，修复完成。

---

## 8. 为什么出事的旧会话救不回来

- DSH 把会话的全部往来记录在日志文件 `session.jsonl` 中。`.jsonl` 表示「每行一个 JSON 对象」的文本格式。
- 第 3 节数据流的第 8 步要求**成对写入**：`tool/call`（发起调用的记录）和 `tool/result`（调用结果的记录）必须一一对应。
- 双副本故障发生在写入 tool/call 之后、写入 tool/result 之前。于是日志里留下了只有前一半的记录。
- 每次打开这个旧会话，DSH 把日志内容重新发送给 AI 服务。AI 服务校验时发现「有 tool_calls 但缺少配对的工具结果消息」，直接拒绝整个请求，返回的错误是：

  > An assistant message with 'tool_calls' must be followed by tool messages responding to each 'tool_call_id' (insufficient tool messages following tool_calls message)

- 这是日志数据层面的永久损坏，与双副本是否修好无关：修好只保证**新**会话正常。旧会话中的文字内容可以手动复制出来留档，会话本身无法继续使用。

---

## 9. 预防：装插件前的检查

### 装之前：查询插件的依赖清单

```powershell
npm view 包名 dependencies --json
```

| 片段 | 作用 |
|------|------|
| `npm` | Node.js 的包管理器，也是官方包仓库的命令行客户端 |
| `view 包名` | 查询指定包在仓库中的信息（把「包名」替换为实际插件名） |
| `dependencies` | 只显示 dependencies 字段，即该包声明「安装我时请一并安装的包」 |
| `--json` | 以 JSON 格式输出，结构清晰、便于阅读 |

判读方法：输出中出现以下任何一个包名，说明插件作者把 DSH 核心包写进了 `dependencies`，安装时必然产生第二份副本：

- `@deepseek-ai/dsh-tools`
- `@deepseek-ai/cordis`
- `@deepseek-ai/dsh-subprocess`
- `@deepseek-ai/dsh-commands`

处理：最好不安装。确需安装，装完立刻执行第 6、7 节的确认与清理。

### dependencies 与 peerDependencies 的区别

- `dependencies`：安装我时，把清单里的包**复制一份**装进我的 node_modules，我自己用自己那份。
- `peerDependencies`：声明「我需要这个包，但**不要**帮我安装，由宿主环境提供」。插件与宿主共用同一份代码，同一个 Symbol 值，不会产生双副本。
- 因此，遇到会把核心包写进 dependencies 的插件，正确的长期解法是到插件仓库提交 issue，请作者把核心包从 `dependencies` 移到 `peerDependencies`。

### 四条规则

1. 不在 profile 目录内手动执行 `pnpm install`（会实体化核心包）。
2. 不让 npm 全局安装的 DSH 与 DSH Desktop 共用同一个 `$DSH_HOME`。
3. 不依赖 pnpm 的 overrides 配置来解决此问题：它只锁定版本号，不能阻止实体复制，实测无效。
4. 每次安装插件后，用第 6 节的命令检查一次 LinkType。

---

## 10. 常见问题 FAQ

**Q：重启电脑有用吗？**
A：没有。多出来的代码副本保存在磁盘上，重启不会消失。

**Q：把插件升级到最新版有用吗？**
A：没有。故障与版本号无关，只与核心代码存在几份实体有关。

**Q：卸载插件后为什么还是失败？**
A：卸载动作通常不删除已经复制进来的文件。继续执行第 7 节第 2、3 步。

**Q：删除 node_modules 会丢失配置或聊天记录吗？**
A：不会。配置和会话记录不存放在 node_modules 里，那里只有可重新获取的代码副本。

**Q：官方会修复吗？**
A：此问题在 0.1.0-rc.6 属已知高发问题，社区已完成源码级定位。官方修复发布前，本教程的手动方法是主要处理手段。

**Q：我的 profile 不叫 web 怎么办？**
A：把命令里的 `web` 全部替换为你的 profile 名称。用 `dsh plugin --profile 你的profile名 list` 可以确认名称是否正确。

---

## 11. 完整数据流总结：修复前与修复后

**修复前（故障状态），以执行一条命令为例：**

1. 用户发送消息「帮我执行 xxx 命令」
2. DSH 把会话历史发送给 AI 服务
3. AI 返回 tool_calls：要求调用 pwsh 工具
4. agent-loop 取出该调用，把 tool/call 写入 session.jsonl
5. agent-loop 用 B 副本的 Symbol 去 ctx.tools 查找调度器 → **查不到，返回 undefined**
6. 在 undefined 上读取 .prepare → **抛出 Cannot read properties of undefined (reading 'prepare')**
7. 工具没有执行，tool/result 没有写入日志
8. AI 收到错误，重试再次失败；旧会话日志因缺少 result 配对，后续被 AI 服务整体拒绝

**修复后（正常状态）：**

1. 用户发送消息「帮我执行 xxx 命令」
2. DSH 把会话历史发送给 AI 服务
3. AI 返回 tool_calls：要求调用 pwsh 工具
4. agent-loop 取出该调用，把 tool/call 写入 session.jsonl
5. 用同一个 Symbol 值查到调度器服务
6. prepare 完成工具定义查找与参数校验
7. PowerShell 执行命令，返回输出
8. tool/result 与 tool/call 成对写入 session.jsonl
9. 工具结果发回 AI，AI 生成最终回答，用户看到命令输出

对比结论：故障点集中在第 5 步（Symbol 查找），修复的目标就是恢复「全机器只有一份核心代码」这一前提。

---

## 12. 术语表

| 术语 | 含义 |
|------|------|
| Symbol | JavaScript 的原始数据类型。每次 `Symbol()` 调用产生一个全新唯一的值，即使描述文字相同也不相等。常作为对象键，实现访问隔离 |
| undefined | JavaScript 表示「值不存在」的特殊值。在不存在的值上读取属性会抛出 TypeError |
| TypeError | JavaScript 的错误类型之一：对错误类型的值执行了不合法的操作，例如从 undefined 读属性 |
| node_modules | 固定名称目录，包管理器把代码包及其依赖存放在此 |
| 软链 / Junction / SymbolicLink | 文件系统层面的目录引用，本身不存放文件，指向真实位置。LinkType 属性有值 |
| 实体目录 | 真实存放文件的目录，LinkType 属性为空白 |
| 就近解析 | Node.js 查找依赖包的规则：从当前文件目录逐级向上寻找 node_modules，使用找到的最近一份 |
| pnpm / npm | 包管理器。npm 是 Node.js 官方工具，pnpm 是第三方实现，DSH 用 pnpm 管理插件 |
| dependencies | package.json 的字段：安装本包时需要一并复制安装的依赖清单 |
| peerDependencies | package.json 的字段：声明需要某依赖但不安装，由宿主环境提供 |
| `$DSH_HOME` | DSH 主数据目录，默认 `C:\Users\用户名\.dsh`，profiles、插件、会话数据都在其中 |
| session.jsonl | 会话日志文件，每行一个 JSON 对象，tool/call 与 tool/result 需成对出现 |
| API 400 | AI 服务端认为请求不合法而拒绝。本教程场景下由日志缺少 result 配对引发 |

---

## 13. 资料来源

1. 社区源码级分析（dshdocs.com 等社区整理的「双副本 Symbol 失配」根因与修复路径；来源由用户提供，未逐条独立核实）。
2. DSH 社区 issue #227（npm 全局版与 DSH Desktop 共用 `$DSH_HOME` 的双运行时场景）。
3. 一线实战记录（2026-08：症状确认 → 手动四步修复 → 痊愈判据 → 预防清单，其中「html-void-elements 非软链空目录卡住自愈」为实机发现并验证）。

---

## 14. 哪一节还没看懂

本教程的目标是每一节都能被零基础读者读懂。如果某一节没看懂：

1. 在本仓库提交 issue（页面点 Issues → New issue），标题写「看不懂第 X 节」，正文写你读到哪里卡住、当时的理解是什么。
2. 收到 issue 后，对应章节会按反馈改写得更细。

---

## 附录 A：check_dual_copy.ps1 脚本讲解

### 整体结构

脚本共 4 段：

1. 头部注释与全局设置
2. 路径准备
3. 检查函数 Show-Entries 的定义
4. 三层检查与结论输出

### 逐段讲解

**第 1 段：头部注释与全局设置**

```powershell
$ErrorActionPreference = 'SilentlyContinue'
```

- `$名字` 是 PowerShell 变量的写法。`ErrorActionPreference` 是 PowerShell 的内置偏好变量，决定「命令出错时怎么办」。
- 赋值为 `SilentlyContinue` 表示：本脚本运行期间，非致命错误（例如目录不存在）不显示错误信息、不中断执行。
- 为什么这么写：体检脚本会遇到各种可能不存在的路径，逐条命令都写 `-ErrorAction` 太重复，全局设置一次更干净。副作用是被掩盖的只会是「路径不存在」这类小问题，不影响检查结论。

**第 2 段：路径准备**

```powershell
$profilesDir = Join-Path $env:USERPROFILE '.dsh\profiles'
```

- `Join-Path` 是内置命令：把两段路径拼接成一个完整路径，自动处理路径分隔符，比手动字符串拼接更可靠。
- `$env:USERPROFILE` 前面已解释：当前用户主目录。这行执行后，`$profilesDir` 的值类似 `C:\Users\ww\.dsh\profiles`。

```powershell
$profileCore = Join-Path $profilesDir 'web\node_modules\@deepseek-ai'
$globalCore  = Join-Path $profilesDir 'node_modules\@deepseek-ai'
$healBlocker = Join-Path $profilesDir 'node_modules\html-void-elements'
```

- 三行同上，分别拼出：profile 层核心包目录、全局层核心包目录、卡自愈的待检目录。
- `$sick = $false`：布尔变量，作为最终结论的标记。初始值 false（假定健康），任何一层发现问题就改为 true。

**第 3 段：检查函数 Show-Entries**

```powershell
function Show-Entries {
    param([string]$Path, [string]$ExpectHint)
```

- `function 名字 { ... }` 定义一个可重复调用的函数；`param(...)` 声明参数。`[string]$Path` 表示参数是字符串类型：要检查的目录；`$ExpectHint` 是发现问题时附加显示的提示文字。

```powershell
    if (-not (Test-Path $Path)) {
        Write-Host "    目录不存在：$Path" -ForegroundColor DarkGray
        return
    }
```

- `Test-Path $Path`：检查路径是否存在，返回 True 或 False。
- `-not` 是逻辑取反。整句：如果目录不存在。
- `Write-Host` 向屏幕输出文字；`-ForegroundColor DarkGray` 用深灰色显示。双引号字符串里的 `$Path` 会被替换成实际值。
- `return` 结束函数，后面的代码不再执行。

```powershell
    foreach ($it in (Get-ChildItem $Path)) {
```

- `foreach (项 in 集合) { ... }` 循环：对集合中每一项执行一次花括号内的代码。`$it` 是当前项（一个目录条目对象）。

```powershell
        if ($it.LinkType) {
            Write-Host ("    [OK] {0}  LinkType={1}" -f $it.Name, $it.LinkType) -ForegroundColor Green
        } else {
            Write-Host ("    [X ] {0}  实体目录" -f $it.Name) -ForegroundColor Red
            $script:sick = $true
        }
```

- `if ($it.LinkType)`：条件判断。PowerShell 中空字符串按 False 处理，所以该条件为真 = 条目是软链；为假 = 实体目录。
- `"...{0}...{1}..." -f a, b` 是 .NET 的格式化写法：`{0}` 被 a 替换，`{1}` 被 b 替换。
- 软链：绿色输出 `[OK]`；实体目录：红色输出 `[X ]`，并把 `$script:sick` 置为 true（`$script:` 前缀表示修改函数外层脚本级的变量，否则函数内赋值只影响局部副本）。

**第 4 段：三层检查与结论**

- 依次调用 `Show-Entries` 检查：profile 层核心包、全局层核心包。
- 再用 `Get-Item` 取 `html-void-elements` 条目，判断它是否存在且 LinkType 为空（即非软链的真实目录），是则提示删除。
- 最后按 `$sick` 输出红/绿结论。

### 为什么脚本只读不改

诊断工具必须没有副作用：无论运行多少次，系统状态都不应被改变。这样「检查」这个动作本身不会引入新问题，你才可以放心地反复运行、反复确认。
