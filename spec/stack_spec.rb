require 'cloudformer/stack'

describe Stack do

  describe 'custom AWS configuration' do
    it 'should load custom config option while initializing cloud formation' do
      config = {stack_name: 'stack',
          :aws_access_key => 'dummy-key',
          :aws_secret_access_key => 'access-key',
          :region => 'ap-southeast-2'}

      mock_cf = double(stacks: {})
      Aws::CloudFormation::Client.should_receive(:new).with(region: config[:region]).and_return(mock_cf)
      Aws::EC2::Client.should_receive(:new).with(region: config[:region])
      stack = Stack.new(config)
      puts "test:: #{Aws::Credentials.instance_variables}"
      Aws.config[:credentials].access_key_id.should be config[:aws_access_key]
      Aws.config[:credentials].secret_access_key.should be config[:aws_secret_access_key]
    end
  end


  describe 'stack formation' do
    before :each do
      @cf = double(Aws::CloudFormation::Client)
      @cf_stack = double(Aws::CloudFormation::Stack)
      #@collection = double(Aws::CloudFormation::StackCollection)
      Aws::CloudFormation.should_receive(:new).and_return(@cf)
      #@collection.should_receive(:[]).and_return(@cf_stack)
      #@cf.should_receive(:stacks).and_return(@collection)
    end

    before :each do
      @config = {stack_name: 'stack',
                :aws_access_key => 'dummy-key',
                :aws_secert_access_key => 'access-key',
                :region => 'ap-southeast-2'}
      @stack = Stack.new(@config)
    end

    describe "when deployed" do
      it "should report as the stack being deployed" do
        @cf_stack.should_receive(:exists?).and_return(true)
        @stack.deployed.should be
      end

      describe "#delete" do
        it "should return a true if delete fails" do
          pending
          @cf_stack.should_receive(:exists?).and_return(false)
          @cf_stack.should_receive(:status)
          @stack.delete.should be
        end
      end
    end

    describe "when stack is not deployed" do
      it "should report as the stack not being deployed" do
        @cf_stack.should_receive(:exists?).and_return(false)
        @stack.deployed.should_not be
      end
    end

    describe "when stack operation throws ValidationError" do
      before :each do
        @cf_stack.should_receive(:exists?).and_return(true)
        File.should_receive(:read).and_return("template")
        @cf.should_receive(:validate_template).and_return({"valid" => true})
        @cf_stack.should_receive(:update).and_raise(AWS::CloudFormation::Errors::ValidationError)
      end

      it "apply should return Failed to signal the error" do
        @stack.apply(nil, nil).should be(:Failed)
      end
    end

    describe "when stack operation throws ValidationError because no updates are to be performed" do
      before :each do
        @cf_stack.should_receive(:exists?).and_return(true)
        File.should_receive(:read).and_return("template")
        @cf.should_receive(:validate_template).and_return({"valid" => true})
        @cf_stack.should_receive(:update).and_raise(AWS::CloudFormation::Errors::ValidationError.new("No updates are to be performed."))
      end

      it "apply should return NoUpdate to signal the error" do
        @stack.apply(nil, nil).should be(:NoUpdates)
      end
    end

    describe "when stack update succeeds" do
      before :each do
        @cf_stack.should_receive(:exists?).at_least(:once).and_return(true)
        File.should_receive(:read).and_return("template")
        @cf.should_receive(:validate_template).and_return({"valid" => true})
        @cf_stack.should_receive(:update).and_return(false)
        @cf_stack.should_receive(:events).and_return([])
        @cf_stack.should_receive(:status).at_least(:once).and_return("UPDATE_COMPLETE")
      end

      it "apply should return Succeeded" do
        @stack.apply(nil, nil).should be(:Succeeded)
      end
    end
  end
end
