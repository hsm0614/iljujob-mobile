//iljujob-server/routes/chat.js

const express = require('express');
const router = express.Router();
const chatController = require('../controllers/chatController');
const { verifyToken } = require('../middlewares/verifyToken');
router.use(verifyToken); // 💥 chat 라우터 전체에 토큰 인증 적용

router.get('/detail/:roomId', chatController.getChatDetail);
router.post('/confirm/:roomId', chatController.confirmHire);

router.post('/start', chatController.startChat);
router.get('/list', chatController.getChatList); // ✅ 있어야 함
router.get('/messages', chatController.getMessages);
router.post('/send', chatController.sendMessage);
router.delete('/leave/:roomId', chatController.leaveChatRoom);  // ← 추가된 부분
router.get('/unread-count', chatController.getUnreadCount);

module.exports = router;