// Translated from DepthChart.cs
// ignore_for_file: non_constant_identifier_names

class DepthChart {
  DepthChart();
  List<PlayerDepthData> mPlayers = [];

  void AddPlayer(String fname, String lname, String position, int depth) {
    mPlayers.add(PlayerDepthData()
      ..fname = fname
      ..lname = lname
      ..position = position
      ..depth = depth);
  }

  @override
  String toString() {
    StringBuffer sb = StringBuffer();
    mPlayers.sort();
    String? currentPos;
    for (int i = 0; i < mPlayers.length; i++) {
      if (currentPos != mPlayers[i].position) {
        currentPos = mPlayers[i].position;
        sb.write('\n');
        sb.write(mPlayers[i].position);
      }
      sb.write(',');
      sb.write(mPlayers[i].fname);
      sb.write(' ');
      sb.write(mPlayers[i].lname);
    }
    String result = sb.toString();
    // TrimStart equivalent
    int start = 0;
    while (start < result.length && (result[start] == ' ' || result[start] == '\n' || result[start] == '\r')) {
      start++;
    }
    return result.substring(start);
  }
}

class PlayerDepthData implements Comparable<PlayerDepthData> {
  String fname = '';
  String lname = '';
  String position = '';
  int depth = 0;

  static List<String> sPositionOrder = [
    'QB', 'RB', 'FB', 'WR', 'TE', 'C', 'G', 'T',
    'DE', 'DT', 'OLB', 'ILB', 'CB', 'FS', 'SS',
    'K', 'P'
  ];

  PlayerDepthData();

  @override
  int compareTo(PlayerDepthData other) {
    int myPositionIndex = sPositionOrder.indexOf(this.position);
    int yourPositionIndex = sPositionOrder.indexOf(other.position);
    if (myPositionIndex == yourPositionIndex)
      return this.depth.compareTo(other.depth);
    else
      return myPositionIndex.compareTo(yourPositionIndex);
  }
}
