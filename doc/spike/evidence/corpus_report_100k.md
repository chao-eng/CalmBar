# LANShare Spike 语料与差分报告

- 结论：PASS
- 语料数：52
- 分片差分不一致：0
- 随机模糊次数：100000，不一致：0

## 语料结果

| 用例 | 期望 | A 状态 | D 状态 | A/D 一致 | 期望一致 | D 原因 |
| --- | --- | --- | --- | --- | --- | --- |
| GET / | 成功 | 成功 | 成功 | 是 | 是 |  |
| HEAD / | 成功 | 成功 | 成功 | 是 | 是 |  |
| GET /api/items | 成功 | 成功 | 成功 | 是 | 是 |  |
| GET /api/download Range | 成功 | 成功 | 成功 | 是 | 是 |  |
| GET keep-alive | 成功 | 成功 | 成功 | 是 | 是 |  |
| GET with body | 成功 | 成功 | 成功 | 是 | 是 |  |
| HTTP/1.0 | 400 | 400 | 400 | 是 | 是 | 请求行格式错误 |
| POST session JSON | 400 | 400 | 400 | 是 | 是 | 连接在消息完成前断开 |
| POST session JSON + body | 成功 | 成功 | 成功 | 是 | 是 |  |
| POST text JSON charset | 成功 | 成功 | 成功 | 是 | 是 |  |
| POST upload multipart | 成功 | 成功 | 成功 | 是 | 是 |  |
| POST session Expect | 成功 | 成功 | 成功 | 是 | 是 |  |
| PATCH method | 405 | 405 | 405 | 是 | 是 | 方法不支持 |
| missing Host | 400 | 400 | 400 | 是 | 是 | Host 缺失或重复 |
| duplicate Host | 400 | 400 | 400 | 是 | 是 | Host 缺失或重复 |
| duplicate CL | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_UNEXPECTED_CONTENT_LENGTH |
| CL + TE | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_CONTENT_LENGTH |
| chunked | 501 | 501 | 501 | 是 | 是 | 不支持 Transfer-Encoding |
| POST no CL | 411 | 411 | 411 | 是 | 是 | POST 缺少 Content-Length |
| session wrong CT | 415 | 415 | 415 | 是 | 是 | 需要 application/json |
| session gbk | 415 | 415 | 415 | 是 | 是 | 不支持的 charset |
| upload no boundary | 400 | 400 | 400 | 是 | 是 | multipart boundary 缺失或超长 |
| upload boundary 71 | 400 | 400 | 400 | 是 | 是 | multipart boundary 缺失或超长 |
| upload wrong CT | 415 | 415 | 415 | 是 | 是 | 需要 multipart/form-data |
| unknown POST | 405 | 405 | 405 | 是 | 是 | POST 路由不支持 |
| download traversal | 403 | 403 | 403 | 是 | 是 | 路径含上跳段 |
| download encoded traversal | 403 | 403 | 403 | 是 | 是 | 路径含上跳段 |
| download double encoding | 400 | 400 | 400 | 是 | 是 | 路径存在双重编码 |
| bad percent | 400 | 400 | 400 | 是 | 是 | 路径含非法百分号编码 |
| absolute form | 400 | 400 | 400 | 是 | 是 | 仅支持 origin-form |
| asterisk form | 400 | 400 | 400 | 是 | 是 | 仅支持 origin-form |
| double slash | 400 | 400 | 400 | 是 | 是 | 仅支持 origin-form |
| NUL target | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_URL |
| bare LF request line | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_VERSION |
| bare LF header | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_CR_EXPECTED |
| obs-fold | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_HEADER_TOKEN |
| header name space | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_HEADER_TOKEN |
| header control byte | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_HEADER_TOKEN |
| header 17KB | 431 | 431 | 431 | 是 | 是 | 请求头超过 16KB |
| header 101 | 431 | 431 | 431 | 是 | 是 | 请求头字段超过 100 个 |
| CL non-numeric | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_CONTENT_LENGTH |
| CL overflow | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_CONTENT_LENGTH |
| CL negative | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_CONTENT_LENGTH |
| Expect invalid | 417 | 417 | 417 | 是 | 是 | 不支持的 Expect |
| Expect duplicate | 417 | 417 | 417 | 是 | 是 | 重复 Expect |
| upload 20GB+9MB | 413 | 413 | 413 | 是 | 是 | 请求体超过 20GB + 8MB |
| session 2MB | 413 | 413 | 413 | 是 | 是 | JSON 请求体超过 1MB |
| HTTP/2.0 | 400 | 400 | 400 | 是 | 是 | 请求行格式错误 |
| HTTP/0.9 | 400 | 400 | 400 | 是 | 是 | 请求行格式错误 |
| empty | 400 | 400 | 400 | 是 | 是 | 连接在请求头完成前断开 |
| headers only | 400 | 400 | 400 | 是 | 是 | llhttp: HPE_INVALID_METHOD |
| duplicate CT upload | 415 | 415 | 415 | 是 | 是 | 需要 multipart/form-data |

## Multipart 流式测试
- PASS multipart 1-byte streaming (25 bytes)
- PASS multipart parts<=8
- PASS multipart part-header<=8KB

## 覆盖率计数
- bodyBytes: 4980
- bodyEvents: 1264
- error_400: 200520
- error_403: 40
- error_405: 40
- error_411: 20
- error_413: 40
- error_415: 80
- error_417: 40
- error_431: 35
- error_501: 20
- headersComplete: 220
- messageComplete: 200
- requestLine: 487
