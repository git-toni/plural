defmodule Core.Schema.UpgradeQueue do
  use Piazza.Ecto.Schema
  alias Core.Schema.User

  @expiry 10

  schema "upgrade_queues" do
    field :acked,     :binary_id
    field :name,      :string
    field :domain,    :string
    field :git,       :string
    field :provider,  Core.Schema.Recipe.Provider
    field :pinged_at, :utc_datetime_usec

    belongs_to :user, User

    timestamps()
  end

  def for_user(query \\ __MODULE__, user_id) do
    from(q in query, where: q.user_id == ^user_id)
  end

  def expired(query \\ __MODULE__) do
    expiry = Timex.now() |> Timex.shift(days: -@expiry)
    from(q in query, where: q.pinged_at < ^expiry)
  end

  @valid ~w(acked user_id name domain git provider)a

  def changeset(model, attrs \\ %{}) do
    model
    |> cast(attrs, @valid)
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:name, name: index_name(:upgrade_queues, [:user_id, :name]))
  end
end
