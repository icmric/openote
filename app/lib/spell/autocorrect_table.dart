/// The words that are corrected silently as they are typed.
///
/// **A list, not a guess.** The checker's own "one letter away" rule fixed
/// `definately` and `seperate`, and it also turned `alot` into *alto*, `isnt`
/// into *inst*, `realy` into *relay* and `dosent` into *docent*: any word the
/// dictionary happens to hold one edit away is "the answer" to it, however
/// rare. A silent wrong change is worse than a typo left underlined, so nothing
/// here is inferred. Every entry is a spelling that is wrong in every context
/// and has exactly one thing it could have meant.
///
/// Two kinds:
///   * **Missing apostrophes**: `dont`, `im`, `youre`. Never `its`, `lets`,
///     `were`, `well` or `ill`, which are words on their own.
///   * **Classic misspellings** that no other word could be.
///
/// No entry depends on the dialect (`recieve` is wrong in every English), and
/// none is a spelling that differs between them (`colour`, `organise`).
/// English only: the caller gates the whole feature on the person writing
/// English, and a word that is not in this list is never touched.
library;

/// The correction for [word], or null to leave it alone.
///
/// Case follows the typed word: `Dont` becomes `Don't`, `dont` becomes `don't`,
/// and an all-capitals word (`DONT`) is left alone, since it is probably an
/// acronym or shouting rather than a slip.
String? autocorrectFor(String word) {
  final lower = word.toLowerCase();
  final fix = _fixes[lower];
  if (fix == null) return null;
  if (word == lower) return fix;
  // Only an initial capital is followed. A capital anywhere else means this is
  // not an ordinary lower-case word, so it is left exactly as typed.
  final initialCapital = word[0] != word[0].toLowerCase() &&
      word.substring(1) == word.substring(1).toLowerCase();
  if (!initialCapital) return null;
  return '${fix[0].toUpperCase()}${fix.substring(1)}';
}

const Map<String, String> _fixes = {
  // ── Missing apostrophes ─────────────────────────────────────────────────
  'dont': "don't", 'doesnt': "doesn't", 'didnt': "didn't",
  'isnt': "isn't", 'arent': "aren't", 'wasnt': "wasn't", 'werent': "weren't",
  'hasnt': "hasn't", 'havent': "haven't", 'hadnt': "hadn't",
  'wouldnt': "wouldn't", 'couldnt': "couldn't", 'shouldnt': "shouldn't",
  'mustnt': "mustn't", 'neednt': "needn't",
  'cant': "can't", 'wont': "won't",
  'im': "I'm", 'ive': "I've",
  'youre': "you're", 'youve': "you've", 'youll': "you'll",
  'theyre': "they're", 'theyve': "they've", 'theyll': "they'll",
  'weve': "we've",
  'thats': "that's", 'whats': "what's", 'theres': "there's",
  'heres': "here's", 'wheres': "where's", 'whos': "who's",
  'wouldve': "would've", 'couldve': "could've", 'shouldve': "should've",
  'mustve': "must've",

  // ── Letters swapped or dropped in very common words ─────────────────────
  'teh': 'the', 'hte': 'the', 'adn': 'and', 'taht': 'that', 'thta': 'that',
  'waht': 'what', 'wiht': 'with', 'wtih': 'with', 'jsut': 'just',
  'abotu': 'about', 'aobut': 'about', 'tehy': 'they', 'thier': 'their',
  'thsi': 'this', 'tihs': 'this', 'whihc': 'which', 'wich': 'which',
  'wihch': 'which', 'whcih': 'which', 'alot': 'a lot',
  'becuase': 'because', 'becasue': 'because', 'beacuse': 'because',

  // ── Classic misspellings ────────────────────────────────────────────────
  'accomodate': 'accommodate', 'accross': 'across', 'adress': 'address',
  'agressive': 'aggressive', 'apparant': 'apparent',
  'arguement': 'argument', 'basicly': 'basically', 'begining': 'beginning',
  'beleive': 'believe', 'belive': 'believe', 'bizzare': 'bizarre',
  'buisness': 'business', 'calender': 'calendar', 'catagory': 'category',
  'cemetary': 'cemetery', 'cheif': 'chief', 'collegue': 'colleague',
  'comming': 'coming', 'commited': 'committed', 'completly': 'completely',
  'concensus': 'consensus', 'concious': 'conscious',
  'definately': 'definitely', 'definatly': 'definitely',
  'definitly': 'definitely', 'diffrent': 'different',
  'diffrence': 'difference', 'dilema': 'dilemma', 'dissapear': 'disappear',
  'dissapoint': 'disappoint', 'embarass': 'embarrass',
  'enviroment': 'environment', 'exagerate': 'exaggerate',
  'existance': 'existence', 'experiance': 'experience',
  'familar': 'familiar', 'finaly': 'finally', 'foriegn': 'foreign',
  'fourty': 'forty', 'freind': 'friend', 'gaurd': 'guard',
  'goverment': 'government', 'grammer': 'grammar', 'greatful': 'grateful',
  'guarentee': 'guarantee', 'happend': 'happened', 'harrass': 'harass',
  'hieght': 'height', 'immediatly': 'immediately', 'imediately': 'immediately',
  'independant': 'independent', 'inteligent': 'intelligent',
  'interupt': 'interrupt', 'knowlege': 'knowledge', 'lenght': 'length',
  'liason': 'liaison', 'libary': 'library', 'maintainance': 'maintenance',
  'millenium': 'millennium', 'mispell': 'misspell', 'neccessary': 'necessary',
  'necesary': 'necessary', 'noticable': 'noticeable', 'occassion': 'occasion',
  'occassionally': 'occasionally', 'occurance': 'occurrence',
  'occured': 'occurred', 'occurence': 'occurrence',
  'oppurtunity': 'opportunity', 'paralell': 'parallel',
  'parliment': 'parliament', 'peice': 'piece', 'persistant': 'persistent',
  'posession': 'possession', 'prefered': 'preferred',
  'privelege': 'privilege', 'pronounciation': 'pronunciation',
  'publically': 'publicly', 'questionaire': 'questionnaire',
  'realy': 'really', 'recieve': 'receive', 'recieved': 'received',
  'recieving': 'receiving', 'reccomend': 'recommend', 'recomend': 'recommend',
  'refered': 'referred', 'relevent': 'relevant', 'religous': 'religious',
  'remeber': 'remember', 'resistence': 'resistance',
  'responsability': 'responsibility', 'rythm': 'rhythm', 'scedule': 'schedule',
  'seige': 'siege', 'seperate': 'separate', 'sieze': 'seize',
  'similiar': 'similar', 'sincerly': 'sincerely', 'speach': 'speech',
  'succesful': 'successful', 'succesfully': 'successfully',
  'sucess': 'success', 'suprise': 'surprise', 'tendancy': 'tendency',
  'threshhold': 'threshold', 'tomorow': 'tomorrow', 'tommorow': 'tomorrow',
  'tounge': 'tongue', 'truely': 'truly', 'unforseen': 'unforeseen',
  'unfortunatly': 'unfortunately', 'untill': 'until', 'usefull': 'useful',
  'vaccuum': 'vacuum', 'vegatable': 'vegetable', 'wendsday': 'Wednesday',
  'wensday': 'Wednesday', 'wierd': 'weird', 'writting': 'writing',
  'writeing': 'writing', 'yeild': 'yield',
};
