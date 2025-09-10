const express = require('express');
const router = express.Router();
const path = require('path');
const multer = require('multer');
const workerController = require('../controllers/workerController');

// 🔧 multer 설정
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/profile/'),
  filename: (req, file, cb) => cb(null, Date.now() + path.extname(file.originalname)),
});
const upload = multer({ storage });

// 📦 회원가입 관련
router.post('/signup', workerController.workerSignup);
router.post('/check', workerController.workerCheck);
router.post('/request-identity-verification', workerController.workerRequestIdentityVerification);

// 📦 프로필 관련
router.get('/profile', workerController.getProfile);
router.patch('/profile', workerController.updateProfile);
router.delete('/profile', workerController.deleteProfile);

// ✅ 프로필 이미지 업로드
router.post(
  '/upload-profile-image',
  upload.single('image'),
  workerController.uploadProfileImage
);

module.exports = router;
