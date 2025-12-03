unless Rails.env.development?
  puts "WARN: Seeding is just for development!"
else
  require "active_support/testing/time_helpers"
  include ActiveSupport::Testing::TimeHelpers

  # Seed DSL
  def seed_account(name)
    print "  #{name}…"
    elapsed = Benchmark.realtime { require_relative "seeds/#{name}" }
    puts " #{elapsed.round(2)} sec"
  end

  def create_tenant(signal_account_name)
    tenant_id = ActiveRecord::FixtureSet.identify signal_account_name
    email_address = "hi@fizzybeads.com"
    identity = Identity.find_or_create_by!(email_address: email_address)

    unless account = Account.find_by(external_account_id: tenant_id)
      account = Account.create_with_owner(
        account: {
          external_account_id: tenant_id,
          name: signal_account_name
        },
        owner: {
          name: "Beads",
          identity: identity
        }
      )
    end
    Current.account = account
  end

  def find_or_create_user(full_name, email_address)
    identity = Identity.find_or_create_by!(email_address: email_address)
    if user = identity.users.find_by(account: Current.account)
      user
    else
      User.create!(name: full_name, identity: identity, account: Current.account)
    end
  end

  def login_as(user)
    Current.session = user.identity.sessions.create
  end

  def create_board(name, creator: Current.user, all_access: true, access_to: [])
    Board.find_or_create_by!(name:, creator:, all_access:).tap { it.accesses.grant_to(access_to) }
  end

  def create_card(title, board:, description: nil, status: :published, creator: Current.user)
    board.cards.create!(title:, description:, creator:, status:)
  end

  # Create minimal account for local beads usage
  tenant_id = ActiveRecord::FixtureSet.identify "fizzybeads"
  email_address = "hi@fizzybeads.com"
  identity = Identity.find_or_create_by!(email_address: email_address)

  unless Account.find_by(external_account_id: tenant_id)
    Account.create_with_owner(
      account: {
        external_account_id: tenant_id,
        name: "fizzybeads"
      },
      owner: {
        name: "Beads",
        identity: identity
      }
    )
  end

  puts "✓ Created fizzybeads account"
  puts "  Login: hi@fizzybeads.com"
end
