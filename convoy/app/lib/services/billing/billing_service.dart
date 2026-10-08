import 'dart:async';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/config/env.dart';
import '../edge/edge_client.dart';

/// Premium subscription through Google Play Billing / StoreKit.
///
/// The store result is never trusted on the device: every purchase is sent
/// to the Worker's `/billing/verify`, which checks it with Google or Apple
/// and writes `entitlements`. The database (vehicle cap trigger) and the app
/// both read that row.
class BillingService {
  BillingService(this._edge, {required this.userId});

  final EdgeClient _edge;
  final String userId;
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _events = StreamController<BillingEvent>.broadcast();

  Stream<BillingEvent> get events => _events.stream;

  Future<List<ProductDetails>> products() async {
    if (!await _iap.isAvailable()) return const [];
    final res = await _iap.queryProductDetails(Env.premiumProductIds);
    final list = res.productDetails.toList()..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    return list;
  }

  void listen() {
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => _events.add(BillingEvent.error('$e')));
  }

  Future<void> buy(ProductDetails p) async {
    listen();
    // applicationUserName ties the purchase to this account (obfuscated
    // account id on Play, appAccountToken on the App Store).
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p, applicationUserName: userId));
  }

  Future<void> restore() async {
    listen();
    await _iap.restorePurchases(applicationUserName: userId);
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(const BillingEvent.pending());
        case PurchaseStatus.error:
          _events.add(BillingEvent.error(p.error?.message ?? 'Purchase failed'));
        case PurchaseStatus.canceled:
          _events.add(const BillingEvent.cancelled());
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            await _edge.post('/billing/verify', {
              'platform': Platform.isIOS ? 'app_store' : 'google_play',
              'product_id': p.productID,
              'purchase_id': p.purchaseID,
              'verification_data': p.verificationData.serverVerificationData,
            });
            _events.add(const BillingEvent.premium());
          } catch (e) {
            _events.add(BillingEvent.error('Could not confirm the purchase yet: $e'));
          }
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _events.close();
  }
}

class BillingEvent {
  const BillingEvent._(this.kind, [this.message]);
  const BillingEvent.pending() : this._('pending');
  const BillingEvent.cancelled() : this._('cancelled');
  const BillingEvent.premium() : this._('premium');
  const BillingEvent.error(String m) : this._('error', m);

  final String kind;
  final String? message;
}
