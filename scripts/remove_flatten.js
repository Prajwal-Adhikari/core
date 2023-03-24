const fs = require('fs');

// 从 `hardhat flatten` 输出中读取内容
let content = fs.readFileSync('./contracts/flattened.sol', 'utf8');
const license = "MIT OR GPL-3.0";

// 删除 SPDX 许可证标识符
content = content.replace(/\/\/ SPDX-License-Identifier: UNLICENSED\n/g, '');
content = content.replace(/\/\/ SPDX-License-Identifier: MIT\n/g, '');

content = `// SPDX-License-Identifier: ${license}\n${content}`;


// 将最终结果写入磁盘
fs.writeFileSync('./contracts/flattened.sol', content);
