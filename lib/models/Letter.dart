class Letter {
  final String char;
  final int score;
  final int totalCount;

  const Letter({required this.char, required this.score, required this.totalCount});
}

const letterPool = [
  Letter(char: 'A', score: 1, totalCount: 12),
  Letter(char: 'B', score: 3, totalCount: 2),
  Letter(char: 'C', score: 4, totalCount: 2),
  Letter(char: 'Ç', score: 4, totalCount: 2),
  Letter(char: 'D', score: 3, totalCount: 2),
  Letter(char: 'E', score: 1, totalCount: 8),
  Letter(char: 'F', score: 7, totalCount: 1),
  Letter(char: 'G', score: 5, totalCount: 1),
  Letter(char: 'Ğ', score: 8, totalCount: 1),
  Letter(char: 'H', score: 5, totalCount: 1),
  Letter(char: 'I', score: 2, totalCount: 4),
  Letter(char: 'İ', score: 1, totalCount: 7),
  Letter(char: 'J', score: 10, totalCount: 1),
  Letter(char: 'K', score: 1, totalCount: 7),
  Letter(char: 'L', score: 1, totalCount: 7),
  Letter(char: 'M', score: 2, totalCount: 4),
  Letter(char: 'N', score: 1, totalCount: 5),
  Letter(char: 'O', score: 2, totalCount: 3),
  Letter(char: 'Ö', score: 7, totalCount: 1),
  Letter(char: 'P', score: 5, totalCount: 1),
  Letter(char: 'R', score: 1, totalCount: 6),
  Letter(char: 'S', score: 2, totalCount: 3),
  Letter(char: 'Ş', score: 4, totalCount: 2),
  Letter(char: 'T', score: 1, totalCount: 5),
  Letter(char: 'U', score: 2, totalCount: 3),
  Letter(char: 'Ü', score: 3, totalCount: 2),
  Letter(char: 'V', score: 7, totalCount: 1),
  Letter(char: 'Y', score: 3, totalCount: 2),
  Letter(char: 'Z', score: 4, totalCount: 2),
  Letter(char: '*', score: 0, totalCount: 2), // Joker
];

final Map<String, int> letterScores = {
  for (final letter in letterPool) letter.char: letter.score,
};


Letter? returnLetterObject(String charParam) {
  if (charParam.isEmpty) {
    return null;
  }
  return letterPool.firstWhere((element) => element.char == charParam);
}

List<String> buildLetterBag() {
  List<String> bag = [];
  for (final letter in letterPool) {
    for (int i = 0; i<letter.totalCount; i++) {
      bag.add(letter.char);
    }
  }
  bag.shuffle();
  return bag;
}

List<String> drawLetters(List<String> bag, int count) {
  return List.generate(count, (_) => bag.removeAt(0));
}
