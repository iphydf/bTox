import 'package:btox/net/dht_actions.dart';
import 'package:btox/net/dht_state.dart';
import 'package:redux/redux.dart';

final dhtReducer = combineReducers<DhtState>([
  TypedReducer<DhtState, AddNodeAction>(_addNode).call,
]);

DhtState _addNode(DhtState state, AddNodeAction action) {
  return state.copyWith(nodes: [...state.nodes, action.node]);
}
