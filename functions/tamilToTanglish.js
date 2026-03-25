/**
 * Tamil to Tanglish (English Transliteration) Converter
 * Converts Tamil Unicode text to English transliteration
 */

// Common Tamil names mapping for accurate transliteration
const commonNames = {
  'குமார்': 'Kumar',
  'சர்வேஷ்': 'Sarvesh',
  'பிரகாஷ்': 'Prakash',
  'ராஜா': 'Raja',
  'கோபாலன்': 'Gopalan',
  'பூசாரி': 'Poosari',
  // Add more common names as needed
};

// Tamil syllable to English phonetic mapping
const syllables = {
  // Compound characters (longer patterns first)
  'பூசாரி': 'Poosari',
  'குமார்': 'Kumar',
  'சர்வேஷ்': 'Sarvesh',
  'பிரகாஷ்': 'Prakash',
  'கோபாலன்': 'Gopalan',
  
  // Common syllables
  'பூ': 'poo',
  'கூ': 'koo',
  'சூ': 'soo',
  'தூ': 'thoo',
  'நூ': 'noo',
  'பு': 'pu',
  'கு': 'ku',
  'சு': 'su',
  'து': 'thu',
  'நு': 'nu',
  'மு': 'mu',
  'ரு': 'ru',
  'லு': 'lu',
  'வு': 'vu',
  'யு': 'yu',
  'று': 'ru',
  'னு': 'nu',
  'பா': 'pa',
  'கா': 'ka',
  'சா': 'sa',
  'தா': 'tha',
  'நா': 'na',
  'மா': 'ma',
  'ரா': 'ra',
  'லா': 'la',
  'வா': 'va',
  'யா': 'ya',
  'றா': 'ra',
  'னா': 'na',
  'பி': 'pi',
  'கி': 'ki',
  'சி': 'si',
  'தி': 'thi',
  'நி': 'ni',
  'மி': 'mi',
  'ரி': 'ri',
  'லி': 'li',
  'வி': 'vi',
  'யி': 'yi',
  'றி': 'ri',
  'னி': 'ni',
  'பே': 'pe',
  'கே': 'ke',
  'சே': 'se',
  'தே': 'the',
  'நே': 'ne',
  'மே': 'me',
  'ரே': 're',
  'லே': 'le',
  'வே': 've',
  'யே': 'ye',
  'றே': 're',
  'னே': 'ne',
  'ப': 'pa',
  'க': 'ka',
  'ச': 'sa',
  'த': 'tha',
  'ந': 'na',
  'ம': 'ma',
  'ர': 'ra',
  'ல': 'la',
  'வ': 'va',
  'ய': 'ya',
  'ற': 'ra',
  'ன': 'na',
};

// Individual Tamil character to English mapping
const tamilToEnglish = {
  'அ': 'a', 'ஆ': 'aa', 'இ': 'i', 'ஈ': 'ee', 'உ': 'u', 'ஊ': 'oo',
  'எ': 'e', 'ஏ': 'ae', 'ஐ': 'ai', 'ஒ': 'o', 'ஓ': 'oo', 'ஔ': 'au',
  'க': 'ka', 'ங': 'nga', 'ச': 'sa', 'ஞ': 'nya', 'ட': 'ta', 'ண': 'na',
  'த': 'tha', 'ந': 'na', 'ப': 'pa', 'ம': 'ma', 'ய': 'ya', 'ர': 'ra',
  'ல': 'la', 'வ': 'va', 'ழ': 'zha', 'ள': 'la', 'ற': 'ra', 'ன': 'na',
  'ஸ': 'sa', 'ஷ': 'sha', 'ஹ': 'ha', 'ஜ': 'ja',
};

/**
 * Check if text contains Tamil Unicode characters
 * Tamil Unicode range: U+0B80 to U+0BFF
 */
function containsTamil(text) {
  if (!text || text.length === 0) return false;
  const tamilRegex = /[\u0B80-\u0BFF]/;
  return tamilRegex.test(text);
}

/**
 * Capitalize first letter of each word
 */
function capitalizeWords(text) {
  return text
    .split(' ')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');
}

/**
 * Convert Tamil text to Tanglish using phonetic mapping
 */
function transliteratePhonetic(tamilText) {
  let result = tamilText;
  
  // Sort syllables by length (longest first) to match compound characters first
  const sortedSyllables = Object.keys(syllables).sort((a, b) => b.length - a.length);
  
  // Replace syllables
  for (const syllable of sortedSyllables) {
    const regex = new RegExp(syllable, 'g');
    result = result.replace(regex, syllables[syllable]);
  }
  
  // Replace remaining individual characters
  for (const char in tamilToEnglish) {
    const regex = new RegExp(char, 'g');
    result = result.replace(regex, tamilToEnglish[char]);
  }
  
  return capitalizeWords(result);
}

/**
 * Main conversion function - converts Tamil to Tanglish
 */
function convertAdvanced(tamilText) {
  if (!tamilText || tamilText.length === 0) return tamilText;
  
  // Check if text contains Tamil
  if (!containsTamil(tamilText)) return tamilText;
  
  // Check common names first
  if (commonNames[tamilText]) {
    return commonNames[tamilText];
  }
  
  // Use phonetic transliteration
  return transliteratePhonetic(tamilText);
}

module.exports = {
  convertAdvanced,
  containsTamil,
};

