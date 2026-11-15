
const mongoose = require("mongoose");
const bcrypt = require("bcryptjs");

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
    },

    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
    },

    avatarUrl: {
  type: String,
  default: null,
},

mission: {
  name: { type: String, default: "" },
  role: { type: String, default: "" },
  status: { type: String, default: "" },
},

preferences: {
  notificationsEnabled: { type: Boolean, default: true },
  temperatureUnit: {
    type: String,
    enum: ["C", "F"],
    default: "C",
  },
},

    password: {
      type: String,
      required: true,
      minlength: 8,
      select: false,
    },

    isVerified: {
      type: Boolean,
      default: false,
    },
    role: {
      type: String,
      enum: ["astronaut", "admin"],
      default: "astronaut",
    },
  },
  { timestamps: true }
);

userSchema.pre("save", async function () {
  if (!this.isModified("password")) return;

  this.password = await bcrypt.hash(this.password, 12);
});

userSchema.methods.comparePassword = async function (password) {
  return bcrypt.compare(password, this.password);
};

userSchema.set("toJSON", {
  transform: (doc, ret) => {
    delete ret.password;
    delete ret.__v;
    return ret;
  },
});

module.exports = mongoose.model("User", userSchema);

