const express = require('express');
const router = express.Router();
const db = require('../models/db');

// ✅ POST /api/report → 신고 등록
router.post('/', async (req, res) => {
  const { jobId, userPhone, reason } = req.body;

  if (!jobId || !userPhone || !reason) {
    return res.status(400).json({ message: '필수 항목이 누락되었습니다.' });
  }

  try {
    await db.query(
      `INSERT INTO job_reports (job_id, user_phone, reason, created_at)
       VALUES (?, ?, ?, NOW())`,
      [jobId, userPhone, reason]
    );

    res.status(200).json({ message: '신고가 접수되었습니다.' });
  } catch (err) {
    console.error('❌ 신고 등록 실패:', err);
    res.status(500).json({ message: '서버 오류' });
  }
});

// ✅ GET /api/report?userPhone= → 내 신고 내역 조회
router.get('/', async (req, res) => {
  const { userPhone } = req.query;

  if (!userPhone) {
    return res.status(400).json({ message: 'userPhone 쿼리 파라미터가 필요합니다.' });
  }

  try {
    const [reports] = await db.query(
      `SELECT id, job_id AS jobId, reason, created_at 
       FROM job_reports 
       WHERE user_phone = ? 
       ORDER BY created_at DESC`,
      [userPhone]
    );
    res.json(reports);
  } catch (err) {
    console.error('❌ 신고 내역 조회 실패:', err);
    res.status(500).json({ message: '서버 오류' });
  }
});

module.exports = router;
