ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Core.Repo, :manual)
Mimic.copy(Stripe.SubscriptionItem.Usage)
