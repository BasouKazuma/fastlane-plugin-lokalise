describe Fastlane::Actions::LokaliseAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The lokalise plugin is working!")

      Fastlane::Actions::LokaliseAction.run(nil)
    end
  end
end
