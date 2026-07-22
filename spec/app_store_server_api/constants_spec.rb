# frozen_string_literal: true

require "spec_helper"

RSpec.describe "protocol constants" do
  describe AppStoreServerApi::NotificationTypeV2 do
    it "exposes Apple's notification types as named constants" do
      expect(described_class::SUBSCRIBED).to eq("SUBSCRIBED")
      expect(described_class::DID_RENEW).to eq("DID_RENEW")
      expect(described_class::GRACE_PERIOD_EXPIRED).to eq("GRACE_PERIOD_EXPIRED")
      expect(described_class::TEST).to eq("TEST")
    end

    it "lists every type in ALL" do
      expect(described_class::ALL).to include("SUBSCRIBED", "DID_RENEW", "EXPIRED", "REVOKE")
      expect(described_class::ALL).to all(be_a(String))
    end
  end

  describe AppStoreServerApi::Subtype do
    it "exposes Apple's subtypes as named constants" do
      expect(described_class::INITIAL_BUY).to eq("INITIAL_BUY")
      expect(described_class::GRACE_PERIOD).to eq("GRACE_PERIOD")
      expect(described_class::BILLING_RETRY).to eq("BILLING_RETRY")
    end

    it "lists every subtype in ALL" do
      expect(described_class::ALL).to include("INITIAL_BUY", "AUTO_RENEW_DISABLED", "VOLUNTARY")
    end
  end

  describe AppStoreServerApi::Status do
    it "maps Apple's subscription status integers to named constants" do
      expect(described_class::ACTIVE).to eq(1)
      expect(described_class::EXPIRED).to eq(2)
      expect(described_class::BILLING_RETRY).to eq(3)
      expect(described_class::BILLING_GRACE_PERIOD).to eq(4)
      expect(described_class::REVOKED).to eq(5)
    end

    describe ".name_for" do
      it "returns the symbol name for a known status" do
        expect(described_class.name_for(1)).to eq(:active)
        expect(described_class.name_for(4)).to eq(:billing_grace_period)
        expect(described_class.name_for(5)).to eq(:revoked)
      end

      it "returns nil for an unknown status" do
        expect(described_class.name_for(99)).to be_nil
        expect(described_class.name_for(nil)).to be_nil
      end
    end
  end
end
