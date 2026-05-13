import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/room_model.dart';

class RoomService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final String roomsCollection = 'rooms';

  /// CREATE ROOM
  Future<void> createRoom(Room room) async {
    await _firestore
        .collection(roomsCollection)
        .doc(room.roomId)
        .set(room.toMap());
  }

  /// GET ROOMS REALTIME
  Stream<List<Room>> getRooms() {
    return _firestore
        .collection(roomsCollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Room.fromMap(doc.data()))
              .toList(),
        );
  }

  /// DELETE ROOM
  Future<void> deleteRoom(String roomId) async {
    await _firestore
        .collection(roomsCollection)
        .doc(roomId)
        .delete();
  }

  /// UPDATE ROOM
  Future<void> updateRoom(
    String roomId,
    Map<String, dynamic> data,
  ) async {
    await _firestore
        .collection(roomsCollection)
        .doc(roomId)
        .update(data);
  }
}