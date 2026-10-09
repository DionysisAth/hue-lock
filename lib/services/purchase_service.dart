import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Store products. Create these ids in App Store Connect and Google Play
/// Console.
class Products {
  /// Non-consumable: no more interstitials.
  static const removeAds = 'hue_lock_remove_ads';

  /// Non-consumable, offered once: remove ads + 1000 coins + the exclusive
  /// Crown ball + 5 continue tokens.
  static const starterPack = 'hue_lock_starter_pack';

  /// Consumable: 5 continue tokens.
  static const tokens5 = 'hue_lock_tokens_5';

  static const all = {removeAds, starterPack, tokens5};
  static const consumables = {tokens5};
}

/// In-app purchases (App Store + Google Play billing).
abstract class PurchaseService extends ChangeNotifier {
  /// Store-localized price, or null while unknown / unavailable.
  String? priceOf(String productId);
  bool get storeAvailable;
  String? get lastError;

  /// [onEntitled] is called for every purchased or restored product.
  Future<void> init({required void Function(String productId) onEntitled});
  Future<void> buy(String productId);
  Future<void> restore();
}

class NoPurchaseService extends PurchaseService {
  @override
  String? priceOf(String productId) => null;
  @override
  bool get storeAvailable => false;
  @override
  String? get lastError => null;
  @override
  Future<void> init({required void Function(String) onEntitled}) async {}
  @override
  Future<void> buy(String productId) async {}
  @override
  Future<void> restore() async {}
}

class StorePurchaseService extends PurchaseService {
  final _iap = InAppPurchase.instance;
  final _products = <String, ProductDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _sub;
  late void Function(String) _onEntitled;
  bool _available = false;
  String? _error;

  @override
  bool get storeAvailable => _available;

  @override
  String? get lastError => _error;

  @override
  String? priceOf(String productId) => _products[productId]?.price;

  @override
  Future<void> init({required void Function(String) onEntitled}) async {
    _onEntitled = onEntitled;
    // Listen before anything else so purchases completed while the app was
    // closed are delivered.
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        _error = '$e';
        notifyListeners();
      },
    );
    _available = await _iap.isAvailable();
    if (_available) {
      final response = await _iap.queryProductDetails(Products.all);
      for (final p in response.productDetails) {
        _products[p.id] = p;
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('Products not found in store: ${response.notFoundIDs}');
      }
    }
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // TODO(backend): validate p.verificationData on a server before
          // granting (design doc 14.4). Local grant is fine for the MVP.
          _onEntitled(p.productID);
          _error = null;
        case PurchaseStatus.error:
          _error = p.error?.message ?? 'Purchase failed';
        case PurchaseStatus.pending:
        case PurchaseStatus.canceled:
          break;
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
    notifyListeners();
  }

  @override
  Future<void> buy(String productId) async {
    final product = _products[productId];
    if (product == null) {
      _error = 'Store not available right now';
      notifyListeners();
      return;
    }
    final param = PurchaseParam(productDetails: product);
    if (Products.consumables.contains(productId)) {
      await _iap.buyConsumable(purchaseParam: param);
    } else {
      await _iap.buyNonConsumable(purchaseParam: param);
    }
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
