# lazarusWeb 工作流程与 DTO 改造示意

> 说明：以下按 **lazarusWeb 默认工作流程** 画图。这是基于其“服务端 LCL 控件树 + JSON 序列化 + Alpine.js 前端渲染”的架构概括，不是逐行源码级时序。

## 1. 总体架构流程图

```mermaid
flowchart TD
    A["浏览器发起请求<br/>GET / 或事件 POST"] --> B["lwhttp Web 服务器<br/>接收 HTTP 请求"]
    B --> C["lwsession 会话管理<br/>创建或获取 Session"]
    C --> D{"会话中是否已有<br/>TLWForm 控件树?"}
    D -- "否" --> E["创建 TLWForm / LCL 控件树<br/>运行在 nogui widgetset 上"]
    D -- "是" --> F["复用服务端已有控件树"]
    E --> G["lwdispatch 事件分发<br/>定位控件并触发事件"]
    F --> G
    G --> H["执行业务逻辑<br/>更新 LCL 控件属性/状态"]
    H --> I["lwwriter 遍历控件树<br/>序列化为 JSON UI 指令"]
    I --> J["返回响应<br/>HTML 壳 + JSON + lw-alpine.js"]
    J --> K["浏览器端 lw-alpine.js<br/>解析 JSON 并构建/更新 DOM"]
    K --> L["用户看到界面并操作"]
    L --> A

    subgraph S["服务端常驻内存"]
        E
        F
        H
        I
    end

    subgraph C2["浏览器端"]
        K
        L
    end
```

核心点：**服务端控件树在会话期间常驻内存**，每次交互后由 `lwwriter` 重新序列化，浏览器端 `lw-alpine.js` 负责解释 JSON 并渲染。

## 2. 一次交互的时序图

```mermaid
sequenceDiagram
    participant B as 浏览器
    participant S as lwhttp/lwsession
    participant W as TLWForm 控件树
    participant D as lwdispatch
    participant R as lwwriter
    participant A as lw-alpine.js

    B->>S: GET / 初始页面请求
    S->>W: 创建或恢复会话控件树
    W-->>R: 提供控件树
    R-->>S: 序列化为 JSON UI 指令
    S-->>B: 返回 HTML + JSON + JS
    B->>A: 加载并初始化
    A->>A: 解析 JSON 构建 DOM

    B->>S: 用户操作事件 POST
    S->>D: 分发事件
    D->>W: 定位控件并触发 OnClick 等
    W->>W: 业务逻辑更新控件状态
    W-->>R: 更新后的控件树
    R-->>S: 重新序列化 JSON
    S-->>B: 返回 JSON 响应
    B->>A: 接收并更新 DOM
```

## 3. 你设想的 DTO 改造后差异点

如果按之前设想的“JSON 输出纯数据 DTO，前端继续用 Alpine.js”，流程图只改中间两段：

```mermaid
flowchart LR
    A["LCL 控件树<br/>业务逻辑与状态"] --> B["lwwriter 改造为<br/>DTO 投影器"]
    B --> C["JSON DTO<br/>纯数据，不是 UI 指令"]
    C --> D["Alpine.js 模板注册表<br/>按 type 选择固定模板"]
    D --> E["前端自主渲染 DOM"]
```

也就是说：**服务端控件树保留，但 JSON 从“UI 指令快照”变成“数据 DTO”，前端从“UI 树解释器”变成“DTO 消费者”**。内存压力不会消失，因为控件树仍常驻服务端；改变的是序列化内容和前端渲染职责。

> 以上 Mermaid 图可直接复制到 Mermaid Live Editor 或支持 Mermaid 的 Markdown 工具中渲染。