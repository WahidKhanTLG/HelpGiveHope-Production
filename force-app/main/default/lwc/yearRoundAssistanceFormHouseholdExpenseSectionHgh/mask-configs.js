export const Currency = {
  mask: "$currency",
  blocks: {
    currency: {
      mask: Number,
      // other options are optional with defaults below
      scale: 2, // digits after point, 0 for integers
      thousandsSeparator: ",", // any single char
      padFractionalZeros: false, // if true, then pads zeros at end to the length of scale
      normalizeZeros: false, // appends or removes zeros at ends
      radix: ".", // fractional delimiter
      mapToRadix: ["."], // symbols to process as radix

      // additional number interval options (e.g.)
      min: 0,
      max: 5000,
      autofix: false,
      validate: (value) => /^0$|^0\.\d{0,2}$|^\.\d{0,2}$|^[1-9]/.test(value)
    }
  }
};

export const DisabledCurrency = {
  mask: "$currency",
  blocks: {
    currency: {
      mask: Number,
      // other options are optional with defaults below
      scale: 2, // digits after point, 0 for integers
      thousandsSeparator: ",", // any single char
      padFractionalZeros: false, // if true, then pads zeros at end to the length of scale
      normalizeZeros: false, // appends or removes zeros at ends
      radix: ".", // fractional delimiter
      mapToRadix: ["."], // symbols to process as radix

      // additional number interval options (e.g.)
      autofix: false
    }
  }
};

export default {
  Currency,
  DisabledCurrency
};