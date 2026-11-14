const nodemailer = require("nodemailer");

async function sendOtpEmail(email, otp, purpose) {
  const {
    SMTP_HOST, SMTP_PORT, SMTP_SECURE, SMTP_USER, SMTP_PASS, EMAIL_FROM
  } = process.env;

  const smtpConfigured = SMTP_HOST && SMTP_PORT && SMTP_USER && SMTP_PASS;

  if (!smtpConfigured) {
    if (process.env.NODE_ENV === "production") {
      throw new Error("Email service is not configured");
    }
    console.log(`\n[DEVELOPMENT OTP] ${purpose} OTP for ${email}: ${otp}\n`);
    return;
  }

  const transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: Number(SMTP_PORT),
    secure: String(SMTP_SECURE).toLowerCase() === "true",
    auth: { user: SMTP_USER, pass: SMTP_PASS }
  });

  await transporter.sendMail({
    from: EMAIL_FROM || SMTP_USER,
    to: email,
    subject: "Your OrbitCare verification code",
    text: `Your OrbitCare verification code is ${otp}. It expires in 10 minutes.`
  });
}

module.exports = sendOtpEmail;
