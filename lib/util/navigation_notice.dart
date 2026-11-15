/// Wortlaut des Hinweises "keine Navigation" (siehe README Abschnitt 70) -
/// eine einzige Stelle für den Dialog beim Start
/// (`ui/navigation_notice_dialog.dart`) und den Abschnitt auf der
/// Info-Seite, damit beide immer dasselbe sagen.
///
/// WICHTIG: Ändert sich der Inhalt wesentlich, muss
/// `AppPreferences.currentNavigationNoticeVersion` erhöht werden - dann
/// erscheint der Hinweis allen Nutzern erneut und muss neu bestätigt werden.
class NavigationNotice {
  NavigationNotice._();

  static const String title = 'Wichtiger Hinweis: keine Navigation!';

  static const List<String> paragraphs = [
    'onTour ist KEIN Navigationsgerät und ist auch nicht zur Navigation gedacht. Die '
        'App ist dafür weder ausgelegt noch geeignet.',
    'Position, Tempo, Kurs, Höhe, Luftdruck, Kompass, Karten und '
        'aufgezeichnete Strecken können ungenau, verzögert oder falsch sein '
        'oder ganz ausfallen - zum Beispiel bei schlechtem GPS-Empfang, '
        'Störungen des Kompasses, leerem Akku oder Fehlern des Geräts oder der '
        'App. Auch Luftlinie und Richtung zu einem Ziel sind keine '
        'Routenführung.',
    'Die verwendeten Karten und Seemarken stammen von Dritten, sind nicht amtlich und '
        'können fehlerhaft oder veraltet sein. Sie ersetzen keine amtliche '
        'Karte und keine Seekarte.',
    'Verlasse dich nicht auf onTour, um einen Weg, einen Kurs oder deinen '
        'Standort zu bestimmen oder um Entscheidungen zu treffen, bei denen '
        'Sicherheit, Gesundheit oder Eigentum auf dem Spiel stehen. Nutze '
        'dafür geeignete Navigationsmittel.',
    'Bediene die App nicht, '
        'während du ein Fahrzeug oder ein Boot führst.',
  ];

  static const String confirmation = 'Ich habe diesen Hinweis gelesen und verstanden: onTour ist nicht zur '
      'Navigation gedacht und eignet sich auch nicht dafür.';
}
