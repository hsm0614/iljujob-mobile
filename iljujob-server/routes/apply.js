// 📁 routes/apply.js
const express = require('express');
const router = express.Router();
const applyController = require('../controllers/applyController');

// 기존 apply 관련 API들
router.post('/apply', applyController.applyToJob);
router.get('/applicant-count/:jobId', applyController.getApplicantCount);
router.post('/check-applied', applyController.checkAlreadyApplied);
router.get('/applicants', applyController.getApplicantsByJobId);

// 🔥 추가: 내가 지원한 공고 리스트
router.get('/applications/my-jobs', applyController.getMyAppliedJobs);

module.exports = router;
