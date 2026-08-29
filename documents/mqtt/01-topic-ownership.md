# 1. Topic ownership

Quy ước: mọi topic dùng chung prefix `device/{deviceId}/...` — không có tiền tố `server/` nào trong code hiện tại. Ai publish topic quyết định bởi named nguồn/đích ở bảng dưới, không suy ra được từ tên topic.

| Topic                             | Direction          | QoS | Retain  | Nguồn/đích hiện tại              | Mục đích                                 |
| --------------------------------- | ------------------ | --- | ------- | -------------------------------- | ---------------------------------------- |
| `device/{id}/status`              | `device -> server` | 1   | `true`  | firmware -> bridge               | online status + LWT offline              |
| `device/{id}/telemetry`           | `device -> server` | 1   | `false` | firmware -> bridge               | sensor telemetry stream                  |
| `device/{id}/response`            | `device -> server` | 1   | `false` | firmware -> bridge               | ack cuối cho command                     |
| `device/{id}/shadow/report`       | `device -> server` | 1   | `false` | firmware -> bridge               | patch reported-state                     |
| `device/{id}/shadow/get`          | `device -> server` | 1   | `false` | firmware -> bridge               | yêu cầu bridge trả `shadow/get_response` |
| `device/{id}/ota/progress`        | `device -> server` | 1   | `false` | firmware -> bridge               | progress OTA                             |
| `device/{id}/command`             | `server -> device` | 1   | `false` | API bridge -> firmware           | imperative command                       |
| `device/{id}/shadow/get_response` | `server -> device` | 1   | `false` | API bridge -> firmware           | desired + delta state                    |
| `device/{id}/ota/update`          | `server -> device` | 1   | `false` | API bridge OTA route -> firmware | trigger OTA (`url` + `sha256`)           |

ACL (`server/api/src/services/emqx.js` — `deviceRules()` / `bridgeRules()`):

- Mỗi device được cấp quyền đúng 9 topic `device/{own_id}/*` ở trên: publish 6 topic đầu, subscribe 3 topic sau — scoped theo device của chính nó (built-in database, mỗi device 1 bộ rule riêng).
- Bridge (`sa-server`) được cấp quyền ngược lại trên wildcard `device/+/*`: subscribe 6 topic đầu, publish 3 topic sau.
- Không có topic broadcast nào (mọi device cùng subscribe 1 topic chung) trong ACL hiện tại.
