# 批次审批（approvals）

批量自主开发（如夜间 dev 分支推进）产出的 commit，按任务时间节点（里程碑）分组为批次文档，owner 逐份审批；审批通过的批次对应 commit 随即合并进 main。

## 流程

1. agent 产出批次文档，命名 `YYYY-MM-DD-<批次标识>-<序号>-<主题>.md`，序号即建议审批顺序。
2. owner 逐份审批：通过 / 驳回 / 有条件通过，结论与意见回填文末「审批记录」。
3. 通过的批次由 agent 合并进 main：批次为 commit 线性前缀，直接 merge 到批次末 commit 即可；非顺序审批或部分驳回时改用 cherry-pick，差异在对应文档中注明。
4. 合并后 agent 提交审批记录并推送；Linear 对应 issue 未闭环的置 Done（附证据）。

仓库为公开仓库（MIT）：本目录文档不得出现密钥等敏感信息。
