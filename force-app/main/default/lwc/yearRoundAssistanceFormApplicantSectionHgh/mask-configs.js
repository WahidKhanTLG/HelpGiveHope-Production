export const SSN = {
  mask: "XXX-XX-0000",
  definitions: {
    X: {
      mask: "0",
      displayChar: "X",
      placeholderChar: "#"
    }
  },
  lazy: false // display placeholder
};

export const Phone = {
  mask: "+{1} (000) 000-0000"
};

export const MonthsOfEmploymentOrUnemployment = {
  mask: Number, // enable number mask

  // other options are optional with defaults below
  scale: 0, // digits after point, 0 for integers
  thousandsSeparator: ",", // any single char
  padFractionalZeros: false, // if true, then pads zeros at end to the length of scale
  normalizeZeros: false, // appends or removes zeros at ends
  radix: ",", // fractional delimiter
  mapToRadix: ["."], // symbols to process as radix

  // additional number interval options (e.g.)
  min: 0,
  max: 100,
  autofix: false
};

export const HoursWorkedPerWeek = {
  mask: Number, // enable number mask

  // other options are optional with defaults below
  scale: 0, // digits after point, 0 for integers
  thousandsSeparator: ",", // any single char
  padFractionalZeros: false, // if true, then pads zeros at end to the length of scale
  normalizeZeros: false, // appends or removes zeros at ends
  radix: ",", // fractional delimiter
  mapToRadix: ["."], // symbols to process as radix

  // additional number interval options (e.g.)
  min: 0,
  max: 60,
  autofix: false
};

export const PayPerHour = {
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
      max: 35,
      autofix: false
    }
  }
};

export const NumberMax2000 = {
  mask: "$currency",
  blocks: {
    currency: {
      mask: Number, // enable number mask

      // other options are optional with defaults below
      scale: 0, // digits after point, 0 for integers
      thousandsSeparator: ",", // any single char
      padFractionalZeros: false, // if true, then pads zeros at end to the length of scale
      normalizeZeros: false, // appends or removes zeros at ends
      radix: ",", // fractional delimiter
      mapToRadix: ["."], // symbols to process as radix

      // additional number interval options (e.g.)
      min: 0,
      max: 2000,
      autofix: false
    }
  }
};

export const NumberMax5000 = {
  mask: "$currency",
  blocks: {
    currency: {
      mask: Number, // enable number mask

      // other options are optional with defaults below
      scale: 0, // digits after point, 0 for integers
      thousandsSeparator: ",", // any single char
      padFractionalZeros: false, // if true, then pads zeros at end to the length of scale
      normalizeZeros: false, // appends or removes zeros at ends
      radix: ",", // fractional delimiter
      mapToRadix: ["."], // symbols to process as radix

      // additional number interval options (e.g.)
      min: 0,
      max: 5000,
      autofix: false
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
  SSN,
  Phone,
  MonthsOfEmploymentOrUnemployment,
  HoursWorkedPerWeek,
  PayPerHour,
  NumberMax2000,
  NumberMax5000,
  DisabledCurrency
};