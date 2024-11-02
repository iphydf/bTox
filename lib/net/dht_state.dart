import 'package:btox/net/crypto.dart';
import 'package:btox/net/model/node_info.dart';
import 'package:sodium/sodium.dart' show Sodium;

final class DhtState {
  final Sodium sodium;
  final KeyPair keyPair;
  final List<NodeInfo> nodes;

  const DhtState(
      {required this.sodium, required this.keyPair, required this.nodes});

  DhtState.initial({required this.sodium, required this.keyPair})
      : nodes = const [];

  DhtState copyWith({
    Sodium? sodium,
    KeyPair? keyPair,
    List<NodeInfo>? nodes,
  }) {
    return DhtState(
      sodium: sodium ?? this.sodium,
      keyPair: keyPair ?? this.keyPair,
      nodes: nodes ?? this.nodes,
    );
  }
}
