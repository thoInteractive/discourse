# frozen_string_literal: true

require 'rails_helper'
require_dependency 'post_action'

describe PostSerializer do
  fab!(:post) { Fabricate(:post) }

  context "a post with lots of actions" do
    fab!(:actor) { Fabricate(:user) }
    fab!(:admin) { Fabricate(:admin) }
    let(:acted_ids) {
      PostActionType.public_types.values
        .concat([:notify_user, :spam].map { |k| PostActionType.types[k] })
    }

    def visible_actions_for(user)
      serializer = PostSerializer.new(post, scope: Guardian.new(user), root: false)
      # NOTE this is messy, we should extract all this logic elsewhere
      serializer.post_actions = PostAction.counts_for([post], actor)[post.id] if user.try(:id) == actor.id
      actions = serializer.as_json[:actions_summary]
      lookup = PostActionType.types.invert
      actions.keep_if { |a| (a[:count] || 0) > 0 }.map { |a| lookup[a[:id]] }
    end

    before do
      acted_ids.each do |id|
        PostActionCreator.new(actor, post, id).perform
      end
      post.reload
    end

    it "displays the correct info" do
      expect(visible_actions_for(actor).sort).to eq([:like, :notify_user, :spam])
      expect(visible_actions_for(post.user).sort).to eq([:like])
      expect(visible_actions_for(nil).sort).to eq([:like])
      expect(visible_actions_for(admin).sort).to eq([:like, :notify_user, :spam])
    end

    it "can't flag your own post to notify yourself" do
      serializer = PostSerializer.new(post, scope: Guardian.new(post.user), root: false)
      notify_user_action = serializer.actions_summary.find { |a| a[:id] == PostActionType.types[:notify_user] }
      expect(notify_user_action).to be_blank
    end

    it "should not allow user to flag post and notify non human user" do
      post.update!(user: Discourse.system_user)

      serializer = PostSerializer.new(post,
        scope: Guardian.new(actor),
        root: false
      )

      notify_user_action = serializer.actions_summary.find do |a|
        a[:id] == PostActionType.types[:notify_user]
      end

      expect(notify_user_action).to eq(nil)
    end
  end

  context "a post with reviewable content" do
    let!(:reviewable) { PostActionCreator.spam(Fabricate(:user), post).reviewable }

    it "includes the reviewable data" do
      json = PostSerializer.new(post, scope: Guardian.new(Fabricate(:moderator)), root: false).as_json
      expect(json[:reviewable_id]).to eq(reviewable.id)
      expect(json[:reviewable_score_count]).to eq(1)
      expect(json[:reviewable_score_pending_count]).to eq(1)
    end
  end

  context "a post by a nuked user" do
    before do
      post.update!(
        user_id: nil,
        deleted_at: Time.zone.now
      )
    end

    subject { PostSerializer.new(post, scope: Guardian.new(Fabricate(:admin)), root: false).as_json }

    it "serializes correctly" do
      [:name, :username, :display_username, :avatar_template, :user_title, :trust_level].each do |attr|
        expect(subject[attr]).to be_nil
      end
      [:moderator, :staff, :yours].each do |attr|
        expect(subject[attr]).to eq(false)
      end
    end
  end

  context "display_username" do
    let(:user) { post.user }
    let(:serializer) { PostSerializer.new(post, scope: Guardian.new, root: false) }
    let(:json) { serializer.as_json }

    it "returns the display_username it when `enable_names` is on" do
      SiteSetting.enable_names = true
      expect(json[:display_username]).to be_present
    end

    it "doesn't return the display_username it when `enable_names` is off" do
      SiteSetting.enable_names = false
      expect(json[:display_username]).to be_blank
    end
  end

  context "a hidden post with add_raw enabled" do
    let(:user) { Fabricate.build(:user, id: 101) }
    let(:raw)  { "Raw contents of the post." }

    def serialized_post_for_user(u)
      s = PostSerializer.new(post, scope: Guardian.new(u), root: false)
      s.add_raw = true
      s.as_json
    end

    context "a public post" do
      let(:post) { Fabricate.build(:post, raw: raw, user: user) }

      it "includes the raw post for everyone" do
        [nil, user, Fabricate(:user), Fabricate(:moderator), Fabricate(:admin)].each do |user|
          expect(serialized_post_for_user(user)[:raw]).to eq(raw)
        end
      end
    end

    context "a hidden post" do
      let(:post) { Fabricate.build(:post, raw: raw, user: user, hidden: true, hidden_reason_id: Post.hidden_reasons[:flag_threshold_reached]) }

      it "shows the raw post only if authorized to see it" do
        expect(serialized_post_for_user(nil)[:raw]).to eq(nil)
        expect(serialized_post_for_user(Fabricate(:user))[:raw]).to eq(nil)

        expect(serialized_post_for_user(user)[:raw]).to eq(raw)
        expect(serialized_post_for_user(Fabricate(:moderator))[:raw]).to eq(raw)
        expect(serialized_post_for_user(Fabricate(:admin))[:raw]).to eq(raw)
      end

      it "can view edit history only if authorized" do
        expect(serialized_post_for_user(nil)[:can_view_edit_history]).to eq(false)
        expect(serialized_post_for_user(Fabricate(:user))[:can_view_edit_history]).to eq(false)

        expect(serialized_post_for_user(user)[:can_view_edit_history]).to eq(true)
        expect(serialized_post_for_user(Fabricate(:moderator))[:can_view_edit_history]).to eq(true)
        expect(serialized_post_for_user(Fabricate(:admin))[:can_view_edit_history]).to eq(true)
      end
    end

    context "a hidden revised post" do
      let(:post) { Fabricate(:post, raw: 'Hello world!', hidden: true) }

      before do
        SiteSetting.editing_grace_period_max_diff = 1

        revisor = PostRevisor.new(post)
        revisor.revise!(post.user, raw: 'Hello, everyone!')
      end

      it "will not leak version to users" do
        json = PostSerializer.new(post, scope: Guardian.new(user), root: false).as_json
        expect(json[:version]).to eq(1)
      end

      it "will show real version to staff" do
        json = PostSerializer.new(post, scope: Guardian.new(Fabricate(:admin)), root: false).as_json
        expect(json[:version]).to eq(2)
      end
    end

    context "a public wiki post" do
      let(:post) { Fabricate.build(:post, raw: raw, user: user, wiki: true) }

      it "can view edit history" do
        [nil, user, Fabricate(:user), Fabricate(:moderator), Fabricate(:admin)].each do |user|
          expect(serialized_post_for_user(user)[:can_view_edit_history]).to eq(true)
        end
      end
    end

    context "a hidden wiki post" do
      let(:post) {
        Fabricate.build(
          :post,
          raw: raw,
          user: user,
          wiki: true,
          hidden: true,
          hidden_reason_id: Post.hidden_reasons[:flag_threshold_reached])
      }

      it "can view edit history only if authorized" do
        expect(serialized_post_for_user(nil)[:can_view_edit_history]).to eq(false)
        expect(serialized_post_for_user(Fabricate(:user))[:can_view_edit_history]).to eq(false)
        expect(serialized_post_for_user(user)[:can_view_edit_history]).to eq(true)
        expect(serialized_post_for_user(Fabricate(:moderator))[:can_view_edit_history]).to eq(true)
        expect(serialized_post_for_user(Fabricate(:admin))[:can_view_edit_history]).to eq(true)
      end
    end

  end

  context "a post with notices" do
    let(:user) { Fabricate(:user, trust_level: 1) }
    let(:user_tl1) { Fabricate(:user, trust_level: 1) }
    let(:user_tl2) { Fabricate(:user, trust_level: 2) }

    let(:post) {
      post = Fabricate(:post, user: user)
      post.custom_fields["notice_type"] = Post.notices[:returning_user]
      post.custom_fields["notice_args"] = 1.day.ago
      post.save_custom_fields
      post
    }

    def json_for_user(user)
      PostSerializer.new(post, scope: Guardian.new(user), root: false).as_json
    end

    it "is visible for TL2+ users (except poster)" do
      expect(json_for_user(nil)[:notice_type]).to eq(nil)
      expect(json_for_user(user)[:notice_type]).to eq(nil)

      SiteSetting.returning_user_notice_tl = 2
      expect(json_for_user(user_tl1)[:notice_type]).to eq(nil)
      expect(json_for_user(user_tl2)[:notice_type]).to eq(Post.notices[:returning_user])

      SiteSetting.returning_user_notice_tl = 1
      expect(json_for_user(user_tl1)[:notice_type]).to eq(Post.notices[:returning_user])
      expect(json_for_user(user_tl2)[:notice_type]).to eq(Post.notices[:returning_user])
    end
  end

end
