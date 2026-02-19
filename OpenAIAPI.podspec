Pod::Spec.new do |s|
	s.name         			= "OpenAIAPI"
	s.version      			= "3.3"
	s.ios.deployment_target = '12.0'
	s.summary      			= 'OpenAIAPI'
	s.homepage         		= 'https://OpenAIAPI.com'
	s.license 				= { :type => 'MIT', :file => 'LICENSE' }
	s.author           		= { "OpenAIAPI" => "OpenAIAPI@OpenAIAPI.com" }
	s.social_media_url 		= 'https://OpenAIAPI.com'
	s.source           		= { :git => "git@github.com:astrokin/OpenAISwift.git", :tag => s.version.to_s }
	s.source_files 			= 'Sources/**/*.swift'
	s.swift_version 		= '5.5'
	s.static_framework 		= true
	s.frameworks 			= 'Foundation'
end
