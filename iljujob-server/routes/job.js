const express = require('express');
const router = express.Router();
const path = require('path');
const multer = require('multer');
const db = require('../models/db');

const jobController = require('../controllers/jobController');
const applyController = require('../controllers/applyController');
const chatController = require('../controllers/chatController');

// 🔧 이미지 업로드용 multer 설정
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/'),
  filename: (req, file, cb) => cb(null, Date.now() + path.extname(file.originalname)),
});
const upload = multer({ storage });

/* 
===================================================
✅ 공고 관련 라우팅
===================================================
*/

// 🔹 1. 공고 등록 (신규 + 재공고 모두 여기서 처리)
router.post('/post_job', upload.single('image'), jobController.postJob);

// 🔹 2. 전체 공고 불러오기 (구직자 홈)
router.get('/jobs', jobController.getAllJobs);

// 🔹 3. 단일 공고 불러오기 (공고 상세 페이지용)
router.get('/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await db.query('SELECT * FROM jobs WHERE id = ?', [id]);
    if (rows.length === 0) {
      return res.status(404).send({ message: 'Job not found' });
    }
    res.send(rows[0]);
  } catch (err) {
    console.error('❌ 단일 공고 조회 실패', err);
    res.status(500).send({ message: '서버 오류' });
  }
});

// 🔹 4. 공고 수정 (EditJobScreen → update 용)
// created_at 필드 절대 수정 안함 ⚠️
router.put('/:id', async (req, res) => {
  const { id } = req.params;

  // ✅ 요청에서 필요한 값 추출
  const {
    title,
    pay,
    description,
    category,
    payType,
    location,
    start_time,
    end_time,
    startDate,
    endDate,
    weekdays,
  } = req.body;

  try {
    await db.query(
      `
      UPDATE jobs SET
        title = ?,
        pay = ?,
        description = ?,
        category = ?,
        pay_type = ?,
        location = ?,
        start_time = ?,
        end_time = ?,
        start_date = ?,
        end_date = ?,
        weekdays = ?
      WHERE id = ?
    `,
      [
        title,
        pay,
        description,
        category,
        payType,
        location,
        start_time,
        end_time,
        startDate || null,
        endDate || null,
        weekdays || null,
        id,
      ]
    );

    res.send({ message: '공고가 수정되었습니다.' });
  } catch (err) {
    console.error('❌ 공고 수정 실패:', err);
    res.status(500).send({ message: '서버 오류' });
  }
});

/* 
===================================================
🟦 지원 및 채팅 관련 라우팅
=================================================== */
router.get('/:jobId/applicant-count', applyController.getApplicantCount);
router.post('/check-applied', applyController.checkAlreadyApplied);

// 🔹 지원하기 (구직자 → 공고 지원)
router.post('/apply', applyController.applyToJob);

// 🔹 채팅방 생성 (공고 단위)
router.post('/start-chat', chatController.startChat);

module.exports = router;
