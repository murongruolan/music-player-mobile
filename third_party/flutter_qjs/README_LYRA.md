# flutter_qjs（随仓库附带）

- 来源：https://github.com/ekibun/flutter_qjs ，tag `v0.4.0`（提交 12a393b），MIT。
- `cxx/quickjs`：quickjs-ng（https://github.com/quickjs-ng/quickjs ，提交 081d50c），MIT；
  去掉了 `.git`、`docs/` 和 `test262` 子模块，其余原样。
- 为什么放进仓库：0.4.0（改用 Dart build hooks 从源码编译，支持 AGP 9 / flutter test）还没发布到 pub.dev，
  pub 的 git 依赖又不会拉取 quickjs-ng 子模块。上游发布到 pub.dev 后可以删掉本目录，改回版本依赖。
- 未做任何修改。
