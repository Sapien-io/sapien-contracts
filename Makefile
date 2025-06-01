unit    :; FOUNDRY_PROFILE=default forge test
invar   :; FOUNDRY_PROFILE=invariant forge test

fmt     :;  FOUNDRY_PROFILE=default forge fmt && FOUNDRY_PROFILE=mainnet forge fmt

lint    :;  solhint --fix --noPrompt test/**/*.sol && \
            solhint --fix --noPrompt src/**/*.sol && \
            solhint --fix --noPrompt script/**/*.sol

# Coverage https://github.com/linux-test-project/lcov (brew install lcov)
cover   :;  FOUNDRY_PROFILE=default forge coverage --report lcov \
            --no-match-coverage "(test|script)" \
            --report-file default_coverage.info && \
            lcov --ignore-errors inconsistent \
            -a default_coverage.info -o lcov.info && \
            rm default_coverage.info && \
            genhtml lcov.info -o coverage/

show    :;  npx http-server ./coverage