
// 📁 iljujob-server/controllers/inquiryController.js
const db = require('../models/db');

exports.getList = async (req, res) => {
  const userPhone = req.query.userPhone;

  try {
    const [rows] = await db.query(
      'SELECT id, inquiry_type AS inquiryType, title, content, created_at FROM inquiries WHERE user_phone = ? ORDER BY created_at DESC',
      [userPhone]
    );
    res.json(rows);
  } catch (err) {
    console.error('❌ 문의 내역 조회 실패:', err);
    res.status(500).json({ error: '서버 오류' });
  }
};
