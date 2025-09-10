const db = require('../models/db');

exports.addBookmark = async (req, res) => {
  const { userPhone, jobId } = req.body;
  try {
    await db.query(
      'INSERT INTO bookmarks (user_phone, job_id) VALUES (?, ?)',
      [userPhone, jobId]
    );
    res.json({ success: true, message: '북마크 추가됨' });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      res.status(409).json({ success: false, message: '이미 북마크됨' });
    } else {
      console.error('❌ 북마크 추가 실패:', err);
      res.status(500).json({ success: false, message: '서버 오류' });
    }
  }
};

exports.removeBookmark = async (req, res) => {
  const { userPhone, jobId } = req.body;
  try {
    await db.query(
      'DELETE FROM bookmarks WHERE user_phone = ? AND job_id = ?',
      [userPhone, jobId]
    );
    res.json({ success: true, message: '북마크 제거됨' });
  } catch (err) {
    console.error('❌ 북마크 제거 실패:', err);
    res.status(500).json({ success: false, message: '서버 오류' });
  }
};

exports.getBookmarks = async (req, res) => {
  const { userPhone } = req.query;
  try {
    const [rows] = await db.query(
      `SELECT j.*
       FROM bookmarks b
       JOIN jobs j ON b.job_id = j.id
       WHERE b.user_phone = ?
       ORDER BY b.bookmarked_at DESC`,
      [userPhone]
    );
    res.json(rows);
  } catch (err) {
    console.error('❌ 북마크 리스트 불러오기 실패:', err);
    res.status(500).json({ success: false, message: '서버 오류' });
  }
};
