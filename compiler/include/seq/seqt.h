#ifndef SEQ_SEQT_H
#define SEQ_SEQT_H

#include <iostream>
#include "types.h"

namespace seq {
	namespace types {

		class BaseSeqType : public Type {
		protected:
			explicit BaseSeqType(std::string name);
		public:
			BaseSeqType(BaseSeqType const&)=delete;
			void operator=(BaseSeqType const&)=delete;

			llvm::Value *eq(llvm::Value *self,
			                llvm::Value *other,
			                llvm::BasicBlock *block);

			llvm::Value *defaultValue(llvm::BasicBlock *block) override;

			void initFields() override;
			bool isAtomic() const override;
			llvm::Type *getLLVMType(llvm::LLVMContext& context) const override;
			size_t size(llvm::Module *module) const override;

			virtual llvm::Value *make(llvm::Value *ptr, llvm::Value *len, llvm::BasicBlock *block)=0;
		};

		class SeqType : public BaseSeqType {
		private:
			SeqType();
		public:
			llvm::Value *memb(llvm::Value *self,
			                  const std::string& name,
			                  llvm::BasicBlock *block) override;

			llvm::Value *setMemb(llvm::Value *self,
			                     const std::string& name,
			                     llvm::Value *val,
			                     llvm::BasicBlock *block) override;

			void initOps() override;
			llvm::Value *make(llvm::Value *ptr, llvm::Value *len, llvm::BasicBlock *block) override;
			static SeqType *get() noexcept;
		};

		class StrType : public BaseSeqType {
		private:
			StrType();
		public:
			llvm::Value *memb(llvm::Value *self,
			                  const std::string& name,
			                  llvm::BasicBlock *block) override;

			llvm::Value *setMemb(llvm::Value *self,
			                     const std::string& name,
			                     llvm::Value *val,
			                     llvm::BasicBlock *block) override;

			void initOps() override;
			llvm::Value *make(llvm::Value *ptr, llvm::Value *len, llvm::BasicBlock *block) override;
			static StrType *get() noexcept;
		};

	}
}

#endif /* SEQ_SEQT_H */