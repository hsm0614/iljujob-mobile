const express = require('express');
const router = express.Router();
const bookmarkController = require('../controllers/bookmarkController');

router.post('/add', bookmarkController.addBookmark);
router.post('/remove', bookmarkController.removeBookmark);
router.get('/list', bookmarkController.getBookmarks);

module.exports = router;
