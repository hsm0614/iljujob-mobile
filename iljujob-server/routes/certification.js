// routes/certification.js
const express = require('express');
const router = express.Router();
const { v4: uuidv4 } = require('uuid');

router.post('/api/certification-url', async (req, res) => {
  const identityVerificationId = `identity-verification-${uuidv4()}`;
  const impKey = process.env.IMP_KEY;

  const redirectUrl = `https://albailju.co.kr/verify/redirect?identityVerificationId=${identityVerificationId}`;
  const certificationUrl = `https://cert.portone.io?imp_key=${impKey}&merchant_uid=${identityVerificationId}&redirect_url=${redirectUrl}`;

  res.json({ certificationUrl });
});

module.exports = router;
