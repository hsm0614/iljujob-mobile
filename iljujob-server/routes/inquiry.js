const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const db = require('../models/db');
const inquiryController = require('../controllers/inquiryController');

// 이미지 업로드 설정
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/inquiries/'),
  filename: (req, file, cb) => cb(null, Date.now() + path.extname(file.originalname)),
});
const upload = multer({ storage });

// 문의 등록 API → POST /api/inquiries
router.post('/', upload.array('images', 3), async (req, res) => {
  const { userPhone, inquiryType, title, content } = req.body;

  try {
    const [result] = await db.query(
      'INSERT INTO inquiries (user_phone, inquiry_type, title, content) VALUES (?, ?, ?, ?)',
      [userPhone, inquiryType, title, content]
    );
    const inquiryId = result.insertId;

    if (req.files && req.files.length > 0) {
      for (const file of req.files) {
        await db.query(
          'INSERT INTO inquiry_images (inquiry_id, image_path) VALUES (?, ?)',
          [inquiryId, `/uploads/inquiries/${file.filename}`]
        );
      }
    }

    res.status(200).json({ message: '문의가 등록되었습니다.', inquiryId });
  } catch (err) {
    console.error('❌ 문의 등록 실패:', err);
    res.status(500).json({ message: '서버 오류' });
  }
});

// 내 문의 목록 조회 API → GET /api/inquiries?userPhone=...
router.get('/inquiries', inquiryController.getList); 

module.exports = router;
