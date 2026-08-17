import Foundation
import UIKit
import google_mobile_ads

/// Builds the full-screen reel ad view for iOS.
///
/// Constructed in code rather than from a nib: a nib would have to be authored
/// in Xcode and kept in sync by hand, and there is nothing here that layout
/// anchors don't express more clearly.
///
/// As on Android, every asset must be both populated *and* assigned to the
/// matching `…View` property on GADNativeAdView — the SDK tracks clicks and
/// viewability through those, so populating alone renders a correct-looking ad
/// that reports nothing.
class ReelNativeAdFactory: NSObject, FLTNativeAdFactory {

  private enum Palette {
    static let ink = UIColor(red: 0.051, green: 0.047, blue: 0.035, alpha: 1)
    static let parchment = UIColor(red: 0.957, green: 0.937, blue: 0.890, alpha: 1)
    static let muted = UIColor(red: 0.812, green: 0.784, blue: 0.722, alpha: 1)
    static let brass = UIColor(red: 0.816, green: 0.631, blue: 0.231, alpha: 1)
  }

  func createNativeAd(
    _ nativeAd: GADNativeAd,
    customOptions: [AnyHashable: Any]? = nil
  ) -> GADNativeAdView? {
    let adView = GADNativeAdView()
    adView.backgroundColor = Palette.ink

    // Media fills the card — in a reel the creative is the content, not an
    // illustration sitting beside it.
    let mediaView = GADMediaView()
    mediaView.contentMode = .scaleAspectFill
    mediaView.clipsToBounds = true
    mediaView.translatesAutoresizingMaskIntoConstraints = false
    adView.addSubview(mediaView)
    adView.mediaView = mediaView

    let scrim = GradientView()
    scrim.translatesAutoresizingMaskIntoConstraints = false
    scrim.isUserInteractionEnabled = false
    adView.addSubview(scrim)

    let icon = UIImageView()
    icon.contentMode = .scaleAspectFit
    icon.translatesAutoresizingMaskIntoConstraints = false

    let advertiser = UILabel()
    advertiser.font = .systemFont(ofSize: 12, weight: .medium)
    advertiser.textColor = Palette.muted

    let headline = UILabel()
    headline.font = .systemFont(ofSize: 26, weight: .bold)
    headline.textColor = Palette.parchment
    headline.numberOfLines = 3

    let body = UILabel()
    body.font = .systemFont(ofSize: 15)
    body.textColor = Palette.muted
    body.numberOfLines = 3

    let cta = UIButton(type: .system)
    cta.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
    cta.setTitleColor(Palette.ink, for: .normal)
    cta.backgroundColor = Palette.brass
    cta.layer.cornerRadius = 26
    cta.contentEdgeInsets = UIEdgeInsets(top: 14, left: 26, bottom: 14, right: 26)
    // The SDK drives the tap; a target of our own would fight it and could
    // suppress the click the ad is supposed to report.
    cta.isUserInteractionEnabled = false

    let attribution = UIStackView(arrangedSubviews: [icon, advertiser])
    attribution.axis = .horizontal
    attribution.spacing = 10
    attribution.alignment = .center

    let ctaRow = UIStackView(arrangedSubviews: [cta, UIView()])
    ctaRow.axis = .horizontal

    let column = UIStackView(arrangedSubviews: [attribution, headline, body, ctaRow])
    column.axis = .vertical
    column.spacing = 12
    column.setCustomSpacing(20, after: body)
    column.translatesAutoresizingMaskIntoConstraints = false
    adView.addSubview(column)

    NSLayoutConstraint.activate([
      mediaView.topAnchor.constraint(equalTo: adView.topAnchor),
      mediaView.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
      mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      mediaView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),

      scrim.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      scrim.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
      scrim.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
      scrim.heightAnchor.constraint(equalToConstant: 320),

      column.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 24),
      column.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -24),
      column.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -120),

      icon.widthAnchor.constraint(equalToConstant: 34),
      icon.heightAnchor.constraint(equalToConstant: 34),
    ])

    // Populate, then register. Assets are optional per creative — hiding the
    // ones a given ad omits is what stops an otherwise fine ad rendering with
    // gaps in it.
    headline.text = nativeAd.headline
    adView.headlineView = headline

    body.text = nativeAd.body
    body.isHidden = nativeAd.body == nil
    adView.bodyView = body

    cta.setTitle(nativeAd.callToAction, for: .normal)
    ctaRow.isHidden = nativeAd.callToAction == nil
    adView.callToActionView = cta

    icon.image = nativeAd.icon?.image
    icon.isHidden = nativeAd.icon == nil
    adView.iconView = icon

    let credit = nativeAd.advertiser ?? nativeAd.store
    advertiser.text = credit
    advertiser.isHidden = credit == nil
    adView.advertiserView = advertiser

    // Last: this binds the populated views to the ad and starts viewability
    // tracking. Before the assignments it would register an empty view set.
    adView.nativeAd = nativeAd
    return adView
  }
}

/// A bottom-up scrim. `CAGradientLayer` needs its frame kept in step with the
/// view, which is the whole reason this is a subclass rather than a plain
/// `UIView` with a layer added to it.
final class GradientView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  override init(frame: CGRect) {
    super.init(frame: frame)
    guard let gradient = layer as? CAGradientLayer else { return }
    let ink = UIColor(red: 0.051, green: 0.047, blue: 0.035, alpha: 1)
    gradient.colors = [
      ink.withAlphaComponent(0).cgColor,
      ink.withAlphaComponent(0.6).cgColor,
      ink.withAlphaComponent(0.94).cgColor,
    ]
    gradient.locations = [0, 0.45, 1]
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
