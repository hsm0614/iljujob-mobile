const fs = require('fs');
const path = require('path');

const base = path.join(__dirname); // 현재 디렉토리 기준

const folders = [
  'routes',
  'controllers',
  'models',
  'uploads'
];

folders.forEach((folder) => {
  const fullPath = path.join(base, folder);
  if (!fs.existsSync(fullPath)) {
    fs.mkdirSync(fullPath);
    console.log(`📁 폴더 생성됨: ${folder}`);
  } else {
    console.log(`✅ 이미 존재함: ${folder}`);
  }
});