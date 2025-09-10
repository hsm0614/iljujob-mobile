const db = require('../models/db');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');

const JWT_SECRET = 'your_jwt_secret_key'; // 💥 배포시 .env로 관리하세요

exports.signup = async (req, res) => {
  const { phone, password, userType } = req.body;
  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    await db.query(
      'INSERT INTO users (phone, password, user_type) VALUES (?, ?, ?)',
      [phone, hashedPassword, userType]
    );
    res.json({ message: '회원가입 성공' });
  } catch (err) {
    console.error('❌ 회원가입 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};

exports.login = async (req, res) => {
  const { phone, password } = req.body;
  try {
    const [users] = await db.query('SELECT * FROM users WHERE phone = ?', [phone]);
    if (users.length === 0) {
      return res.status(401).json({ message: '존재하지 않는 사용자' });
    }
    const user = users[0];
    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: '비밀번호 불일치' });
    }
    const token = jwt.sign(
      { id: user.id, phone: user.phone, userType: user.user_type },
      JWT_SECRET,
      { expiresIn: '7d' }
    );
    res.json({ token });
  } catch (err) {
    console.error('❌ 로그인 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};
