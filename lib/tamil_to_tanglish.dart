// lib/tamil_to_tanglish.dart

/// Tamil to Tanglish (English transliteration) converter
/// Converts Tamil Unicode characters to their English phonetic equivalents
class TamilToTanglish {
  /// Main conversion function - converts Tamil text to Tanglish
  static String convert(String tamilText) {
    if (tamilText.isEmpty) return tamilText;

    String result = '';
    for (int i = 0; i < tamilText.length; i++) {
      final char = tamilText[i];
      final codeUnit = char.codeUnitAt(0);

      // Check if it's a Tamil character (Unicode range: 0B80-0BFF)
      if (codeUnit >= 0x0B80 && codeUnit <= 0x0BFF) {
        result += _tamilToEnglish(char);
      } else {
        // Non-Tamil character - keep as is
        result += char;
      }
    }

    return result;
  }

  /// Convert single Tamil character to English transliteration
  static String _tamilToEnglish(String char) {
    // Tamil Unicode to English transliteration mapping
    final Map<int, String> tamilMap = {
      // Vowels
      0x0B85: 'a',  // அ
      0x0B86: 'aa', // ஆ
      0x0B87: 'i',  // இ
      0x0B88: 'ii', // ஈ
      0x0B89: 'u',  // உ
      0x0B8A: 'uu', // ஊ
      0x0B8E: 'e',  // எ
      0x0B8F: 'ee', // ஏ
      0x0B90: 'ai', // ஐ
      0x0B92: 'o',  // ஒ
      0x0B93: 'oo', // ஓ
      0x0B94: 'au', // ஔ

      // Consonants
      0x0B95: 'k',   // க
      0x0B99: 'ng',  // ங
      0x0B9A: 'ch',  // ச
      0x0B9C: 'j',   // ஜ
      0x0B9E: 'ny',  // ஞ
      0x0B9F: 't',   // ட
      0x0BA3: 'n',   // ண
      0x0BA4: 'th',  // த
      0x0BA8: 'n',   // ந
      0x0BAA: 'p',   // ப
      0x0BAE: 'm',   // ம
      0x0BAF: 'y',   // ய
      0x0BB0: 'r',   // ர
      0x0BB2: 'l',   // ல
      0x0BB5: 'v',   // வ
      0x0BB4: 'zh',  // ழ
      0x0BB1: 'r',   // ற
      0x0BB3: 'l',   // ள
      0x0BB6: 'sh',  // ஷ
      0x0BB7: 'sh',  // ஸ
      0x0BB8: 's',   // ஸ
      0x0BB9: 'h',   // ஹ

      // Special characters
      0x0B82: 'm',   // ஂ (anusvara)
      0x0B83: 'h',   // ஃ (visarga)
    };

    final codeUnit = char.codeUnitAt(0);
    return tamilMap[codeUnit] ?? char;
  }

  /// Convert Tamil text with proper handling of conjuncts and compound characters
  static String convertAdvanced(String tamilText) {
    if (tamilText.isEmpty) return tamilText;

    // Common Tamil names to Tanglish mapping
    final Map<String, String> commonNames = {
      // User provided examples
      'சர்வேஷ்': 'Sarvesh',
      'குமார்': 'Kumar',
      'பிரகாஷ்': 'Prakash',
      'ராஜா': 'Raja',
      'கோபாலன்': 'Gopalan',
      'பூசாரி': 'Poosari',
      
      // Additional common names
      'ராமன்': 'Raman',
      'கிருஷ்ணன்': 'Krishnan',
      'முருகன்': 'Murugan',
      'சிவன்': 'Sivan',
      'விநாயகன்': 'Vinayagan',
      'பெருமாள்': 'Perumal',
      'நாராயணன்': 'Narayanan',
      'வெங்கடேஷ்': 'Venkatesh',
      'சுந்தரம்': 'Sundaram',
      'மணி': 'Mani',
      'செல்வம்': 'Selvam',
      'அருண்': 'Arun',
      'விக்னேஷ்': 'Vignesh',
      'பிரசாந்த்': 'Prasanth',
      'தினேஷ்': 'Dinesh',
      'ரமேஷ்': 'Ramesh',
      'சுரேஷ்': 'Suresh',
      'மகேஷ்': 'Mahesh',
      'ரவி': 'Ravi',
      'கண்ணன்': 'Kannan',
      'மோகன்': 'Mohan',
      'ராஜேஷ்': 'Rajesh',
      'விஜய்': 'Vijay',
      'அஜய்': 'Ajay',
      'சங்கர்': 'Shankar',
      'பாலன்': 'Balan',
      'முத்து': 'Muthu',
      'செல்வி': 'Selvi',
      'லட்சுமி': 'Lakshmi',
      'கமலா': 'Kamala',
      'மீனா': 'Meena',
      'ராதா': 'Radha',
      'பார்வதி': 'Parvathi',
      'சரோஜா': 'Saroj',
      'மாலதி': 'Malathi',
      'ஜெயலட்சுமி': 'Jayalakshmi',
      'பிரியா': 'Priya',
      'கவிதா': 'Kavitha',
      'சுமதி': 'Sumathi',
      'ரேணுகா': 'Renuka',
      'வனிதா': 'Vanitha',
      'அனிதா': 'Anitha',
      'ரேகா': 'Reka',
      'சங்கீதா': 'Sangeetha',
      'பூஜா': 'Poja',
      'கீதா': 'Geetha',
      'ராதிகா': 'Radhika',
      'சுவேதா': 'Swetha',
      'தீபா': 'Deepa',
      'நீதா': 'Neetha',
      'ரேவதி': 'Revathi',
      'ஹேமா': 'Hema',
      'சரிதா': 'Sharitha',
      'வித்யா': 'Vidya',
      'சுபா': 'Subha',
      'உஷா': 'Usha',
      'கிரண்': 'Kiran',
      'அனில்': 'Anil',
      'சந்தீப்': 'Sandeep',
      'அமித்': 'Amit',
      'ராகுல்': 'Rahul',
      'அனுப்': 'Anup',
      'ரோஹித்': 'Rohit',
      'மனோஜ்': 'Manoj',
      'ராஜன்': 'Rajan',
      'சந்தோஷ்': 'Santhosh',
      'ஹரி': 'Hari',
      'கோபி': 'Gopi',
      'மாதவ்': 'Madhav',
      'சுரேந்திரன்': 'Surendran',
      'பிரதீப்': 'Pradeep',
      'அமிதாப்': 'Amitabh',
      'ராஜேந்திரன்': 'Rajendran',
      'விஜயகுமார்': 'Vijaykumar',
      'ராமகிருஷ்ணன்': 'Ramakrishnan',
      'சுப்பிரமணியன்': 'Subramanian',
      'நடராஜன்': 'Natarajan',
      'செல்வராஜ்': 'Selvaraj',
      'பாலசுப்பிரமணியன்': 'Balasubramanian',
      'முரளி': 'Murali',
      'சந்திரன்': 'Chandran',
      'கார்த்திக்': 'Karthik',
      'அருண்': 'Arun',
      'கிரண்': 'Kiran',
      'ராகுல்': 'Rahul',
      'அனுப்': 'Anup',
      'ரோஹித்': 'Rohit',
      'மனோஜ்': 'Manoj',
      'ராஜன்': 'Rajan',
      'சந்தோஷ்': 'Santhosh',
      'ஹரி': 'Hari',
      'கோபி': 'Gopi',
      'மாதவ்': 'Madhav',
      'சுரேந்திரன்': 'Surendran',
      'பிரதீப்': 'Pradeep',
      'அமிதாப்': 'Amitabh',
      'ராஜேந்திரன்': 'Rajendran',
      'விஜயகுமார்': 'Vijaykumar',
      'ராமகிருஷ்ணன்': 'Ramakrishnan',
      'சுப்பிரமணியன்': 'Subramanian',
      'நடராஜன்': 'Natarajan',
      'செல்வராஜ்': 'Selvaraj',
      'பாலசுப்பிரமணியன்': 'Balasubramanian',
      'முரளி': 'Murali',
      'சந்திரன்': 'Chandran',
      'கார்த்திக்': 'Karthik',
    };

    // First check if it's a common name
    String text = tamilText.trim();
    if (commonNames.containsKey(text)) {
      return commonNames[text]!;
    }

    // If not found, try to transliterate character by character
    // This is a simplified approach - for better accuracy, you'd need
    // a more sophisticated transliteration algorithm
    return _transliteratePhonetic(text);
  }

  /// Phonetic transliteration - better handling of Tamil compound characters
  static String _transliteratePhonetic(String tamilText) {
    // This is a simplified phonetic transliteration
    // For production, consider using a proper transliteration library
    
    // Common Tamil syllable patterns (including compound characters)
    final Map<String, String> syllables = {
      // Compound characters with ூ (oo/u)
      'கூ': 'koo',
      'சூ': 'soo',
      'பூ': 'poo',  // Fixed: பூ should be "poo" not "pu"
      'தூ': 'thoo',
      'ரூ': 'roo',
      'லூ': 'loo',
      'வூ': 'voo',
      'மூ': 'moo',
      'நூ': 'noo',
      'ணூ': 'noo',
      'றூ': 'roo',
      'ழூ': 'zhoo',
      'ளூ': 'loo',
      'ஷூ': 'shoo',
      'ஸூ': 'soo',
      'ஹூ': 'hoo',
      
      // Simple characters with ு (u)
      'கு': 'ku',
      'சு': 'su',
      'பு': 'pu',
      'து': 'thu',
      'ரு': 'ru',
      'லு': 'lu',
      'வு': 'vu',
      'மு': 'mu',
      'நு': 'nu',
      'ணு': 'nu',
      'று': 'ru',
      'ழு': 'zhu',
      'ளு': 'lu',
      'ஷு': 'shu',
      'ஸு': 'su',
      'ஹு': 'hu',
      
      // Compound characters with ோ (oo)
      'கோ': 'ko',
      'சோ': 'so',
      'போ': 'po',
      'தோ': 'tho',
      'ரோ': 'ro',
      'லோ': 'lo',
      'வோ': 'vo',
      'மோ': 'mo',
      'நோ': 'no',
      'ணோ': 'no',
      'றோ': 'ro',
      'ழோ': 'zho',
      'ளோ': 'lo',
      'ஷோ': 'sho',
      'ஸோ': 'so',
      'ஹோ': 'ho',
      
      // Simple characters with ஆ (aa)
      'கா': 'ka',
      'சா': 'sa',
      'பா': 'pa',
      'தா': 'tha',
      'ரா': 'ra',
      'லா': 'la',
      'வா': 'va',
      'மா': 'ma',
      'நா': 'na',
      'ணா': 'na',
      'றா': 'ra',
      'ழா': 'zha',
      'ளா': 'la',
      'ஷா': 'sha',
      'ஸா': 'sa',
      'ஹா': 'ha',
      
      // Compound characters with ே (e/ee)
      'கே': 'ke',
      'சே': 'se',
      'பே': 'pe',
      'தே': 'the',
      'ரே': 're',
      'லே': 'le',
      'வே': 've',
      'மே': 'me',
      'நே': 'ne',
      'ணே': 'ne',
      'றே': 're',
      'ழே': 'zhe',
      'ளே': 'le',
      'ஷே': 'she',
      'ஸே': 'se',
      'ஹே': 'he',
      
      // Simple characters with இ (i)
      'கி': 'ki',
      'சி': 'si',
      'பி': 'pi',
      'தி': 'thi',
      'ரி': 'ri',
      'லி': 'li',
      'வி': 'vi',
      'மி': 'mi',
      'நி': 'ni',
      'ணி': 'ni',
      'றி': 'ri',
      'ழி': 'zhi',
      'ளி': 'li',
      'ஷி': 'shi',
      'ஸி': 'si',
      'ஹி': 'hi',
      
      // Additional common patterns
      'சார்': 'sar',
      'வார்': 'var',
      'பார்': 'par',
      'ரார்': 'rar',
      'லார்': 'lar',
    };

    String result = tamilText;
    
    // Replace common syllables - process longer patterns first
    // Sort by length (longer first) to handle compound characters correctly
    final sortedSyllables = syllables.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    
    for (var entry in sortedSyllables) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // If still contains Tamil characters, do basic character mapping
    if (_containsTamil(result)) {
      result = convert(result);
    }

    // Capitalize first letter of each word
    return _capitalizeWords(result);
  }

  /// Check if text contains Tamil characters
  static bool _containsTamil(String text) {
    if (text.isEmpty) return false;
    final tamilRegex = RegExp(r'[\u0B80-\u0BFF]');
    return tamilRegex.hasMatch(text);
  }

  /// Capitalize first letter of each word
  static String _capitalizeWords(String text) {
    if (text.isEmpty) return text;
    
    final words = text.split(' ');
    final capitalized = words.map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + (word.length > 1 ? word.substring(1) : '');
    }).toList();
    
    return capitalized.join(' ');
  }
}

