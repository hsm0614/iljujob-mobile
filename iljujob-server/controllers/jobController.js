// 📁 iljujob-server/controllers/jobController.js
const db = require('../models/db');

// 🔹 공고 등록 (파일 포함)
exports.postJob = async (req, res) => {
  const {
    title, category, location, locationCity,
    startDate, endDate,
    startTime, endTime,
    payType, pay,
    description, userNumber,
    weekdays,
    lat, lng
  } = req.body;

  const imageUrl = req.file ? `/uploads/${req.file.filename}` : null;

  const sql = `
    INSERT INTO jobs (
      userNumber, title, category, location, location_city,
      start_date, end_date, start_time, end_time,
      pay_type, pay, description, image_url, weekdays,
      lat, lng
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `;

  const values = [
    userNumber, title, category, location, locationCity || '',
    startDate || null, endDate || null,
    startTime, endTime, payType, pay,
    description, imageUrl, weekdays || null,
    lat || null, lng || null
  ];

  try {
    const [result] = await db.query(sql, values);
    res.status(200).json({ message: '공고 등록 완료', jobId: result.insertId });
  } catch (err) {
    console.error('❌ 공고 저장 실패:', err);
    res.status(500).send('DB 오류');
  }
};

// 🔹 내 공고 조회
exports.getMyJobs = async (req, res) => {
  const userNumber = req.query.userNumber;

  try {
    const [results] = await db.query(
      'SELECT * FROM jobs WHERE userNumber = ? ORDER BY created_at DESC',
      [userNumber]
    );
    res.json(results);
  } catch (err) {
    console.error('❌ 내 공고 불러오기 실패:', err);
    res.status(500).send('서버 오류');
  }
};

// 🔹 전체 공고 조회 (구직자용)
exports.getAllJobs = async (req, res) => {
  try {
    const [results] = await db.query(
      "SELECT * FROM jobs WHERE status = 'active' ORDER BY created_at DESC"
    );
    res.json(results);
  } catch (err) {
    console.error('❌ 전체 공고 불러오기 실패:', err);
    res.status(500).send('서버 오류');
  }
};
