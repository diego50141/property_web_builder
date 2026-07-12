# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pwb::Seeder do
  describe '.seed_users' do
    let(:website) { FactoryBot.create(:pwb_website) }

    def seed_users
      described_class.instance_variable_set(:@current_website, website)
      described_class.send(:seed_users, 'users.yml')
    ensure
      described_class.instance_variable_set(:@current_website, nil)
    end

    # Regresión: los usuarios del seed se creaban sin UserMembership, y
    # site_admin autoriza vía User#admin_for? (membership activa owner/admin):
    # el admin del seed no podía entrar al panel.
    it 'crea la membership activa que exige el acceso a site_admin' do
      seed_users

      admin = Pwb::User.unscoped.find_by(email: 'admin@example.com')
      expect(admin).to be_present
      expect(admin.admin_for?(website)).to be true

      non_admin = Pwb::User.unscoped.find_by(email: 'non_admin@example.com')
      expect(non_admin.admin_for?(website)).to be false
      expect(non_admin.user_memberships.active.where(website: website, role: 'member')).to exist
    end

    it 'repara usuarios existentes sin membership al re-seedear' do
      FactoryBot.create(:pwb_user, email: 'admin@example.com', admin: true, website: website)

      expect { seed_users }.not_to change { Pwb::User.unscoped.where(email: 'admin@example.com').count }

      admin = Pwb::User.unscoped.find_by(email: 'admin@example.com')
      expect(admin.admin_for?(website)).to be true
    end

    it 'es idempotente' do
      seed_users
      expect { seed_users }.not_to change { Pwb::UserMembership.count }
    end
  end
end
