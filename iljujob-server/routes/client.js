const express = require('express');
const router = express.Router();
const clientController = require('../controllers/clientController');  // ✅ 전체 import로 통일
const jobController = require('../controllers/jobController');

// 🔹 클라이언트 회원 관련
router.post('/signup', clientController.clientSignup);
router.post('/check', clientController.clientCheck);

// 🔹 요약 데이터 (오늘/이번주/이번달 지원자 수)
router.get('/summary', clientController.getSummary);

// 🔹 내 공고 조회 (도급사용)
router.get('/jobs', jobController.getMyJobs);
// GET: 프로필 불러오기
router.get('/profile', clientController.getProfile);

// PATCH: 프로필 수정
router.patch('/profile', clientController.updateProfile);

// DELETE: 회원 탈퇴
router.delete('/profile', clientController.deleteProfile);


module.exports = router;
