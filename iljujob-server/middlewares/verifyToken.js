//iljujob-server/middlewares/verifyToken.js
require('dotenv').config();
const jwt = require('jsonwebtoken');
const SECRET = process.env.JWT_SECRET;

exports.verifyToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    console.log('✅ 받은 Authorization 헤더:', authHeader);  // 👉 여기를 추가!
  
    if (!authHeader) return res.status(401).json({ message: 'No token provided' });
  
    const token = authHeader.split(' ')[1];
    if (!token) return res.status(401).json({ message: 'Invalid token format' });
  
    jwt.verify(token, process.env.JWT_SECRET, (err, decoded) => {
      if (err) {
        console.error('❌ 토큰 검증 실패:', err);
        return res.status(403).json({ message: 'Failed to authenticate token' });
      }
  
      req.user = decoded;
      next();
    });
  };