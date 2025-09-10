//iljujob-server/controllers/applyController.js
const db = require('../models/db');

// 공통된 데이터베이스 쿼리 로직을 별도의 함수로 추출
const queryDatabase = async (sql, params) => {
  try {
    const [rows] = await db.query(sql, params);
    return rows;
  } catch (err) {
    console.error('❌ DB 쿼리 실행 실패:', err);
    throw new Error('DB 쿼리 오류');
  }
};

// 🔹 구직자 채용공고 지원
exports.applyToJob = async (req, res) => {
  const { userPhone, jobId } = req.body;

  // 필수 정보 누락 확인
  if (!userPhone || !jobId) {
    return res.status(400).json({ message: '필수 정보 누락' });
  }

  try {
    // 1️⃣ 중복 지원 확인
    const existing = await queryDatabase(
      'SELECT * FROM applications WHERE user_phone = ? AND job_id = ?',
      [userPhone, jobId]
    );

    if (existing.length > 0) {
      return res.status(409).json({ message: '이미 지원한 공고입니다' });
    }

    // 2️⃣ 새 지원 삽입
    await queryDatabase(
      'INSERT INTO applications (user_phone, job_id) VALUES (?, ?)',
      [userPhone, jobId]
    );

    return res.status(200).json({ message: '지원 완료' });
  } catch (err) {
    return res.status(500).json({ message: '서버 오류' });
  }
};

// 🔹 지원자 수 조회
exports.getApplicantCount = async (req, res) => {
  const jobId = req.params.jobId;

  try {
    const rows = await queryDatabase(
      'SELECT COUNT(*) AS count FROM applications WHERE job_id = ?',
      [jobId]
    );
    res.json({ count: rows[0].count });
  } catch (err) {
    return res.status(500).json({ message: 'DB 오류' });
  }
};

// 🔹 지원 여부 확인
exports.checkAlreadyApplied = async (req, res) => {
  const { userPhone, jobId } = req.body;

  if (!userPhone || !jobId) {
    return res.status(400).json({ message: '필수 정보 누락' });
  }

  try {
    const result = await queryDatabase(
      'SELECT COUNT(*) AS applied FROM applications WHERE user_phone = ? AND job_id = ?',
      [userPhone, jobId]
    );

    res.json({ applied: result[0].applied > 0 });
  } catch (err) {
    return res.status(500).json({ message: '서버 오류' });
  }
};

// 🔹 내가 지원한 공고 리스트
exports.getMyAppliedJobs = async (req, res) => {
  const { userPhone } = req.query;
  
  console.log('✅ [getMyAppliedJobs] userPhone:', userPhone);

  if (!userPhone) {
    return res.status(400).json({ message: 'userPhone 필수' });
  }

  try {
    const rows = await queryDatabase(
      `SELECT j.*
       FROM applications a
       JOIN jobs j ON a.job_id = j.id
       WHERE a.user_phone = ?`,
      [userPhone]
    );

    res.json(rows);
  } catch (err) {
    console.error('❌ DB 오류:', err);
    return res.status(500).json({ message: 'DB 오류' });
  }
};


// 지원자 리스트 조회
exports.getApplicantsByJobId = async (req, res) => {
  const { jobId } = req.query;
  if (!jobId) return res.status(400).json({ message: 'jobId가 필요합니다.' });

  try {
    const [rows] = await db.query(`
      SELECT w.phone, w.name, w.profile_image_url, a.created_at
      FROM applications a
      JOIN workers w ON a.user_phone = w.phone
      WHERE a.job_id = ?
    `, [jobId]);

    res.json({ applicants: rows });
  } catch (err) {
    console.error('❌ 지원자 조회 오류:', err);
    res.status(500).json({ message: '서버 오류' });
  }
};
