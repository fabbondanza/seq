#ifndef SEQ_SEQ_H
#define SEQ_SEQ_H

#include <cstdlib>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <initializer_list>

#include "llvm.h"
#include "func.h"
#include "pipeline.h"
#include "stageutil.h"
#include "var.h"
#include "cell.h"
#include "mem.h"
#include "lambda.h"
#include "io.h"
#include "exc.h"
#include "common.h"
#include "record.h"

#include "parser.h"
#include "expr.h"
#include "numexpr.h"
#include "strexpr.h"
#include "varexpr.h"
#include "arrayexpr.h"
#include "recordexpr.h"
#include "lookupexpr.h"
#include "getelemexpr.h"

namespace seq {

	namespace types {
		static AnyType&    Any    = *AnyType::get();
		static BaseType&   Base   = *BaseType::get();
		static VoidType&   Void   = *VoidType::get();
		static SeqType&    Seq    = *SeqType::get();
		static IntType&    Int    = *IntType::get();
		static FloatType&  Float  = *FloatType::get();
		static BoolType&   Bool   = *BoolType::get();
		static StrType&    Str    = *StrType::get();
		static ArrayType&  Array  = *ArrayType::get();
		static RecordType& Record = *RecordType::get({});
	}

	struct PipelineAggregator {
		SeqModule *base;
		std::vector<Pipeline> pipelines;
		explicit PipelineAggregator(SeqModule *base);
		void add(Pipeline pipeline);
		Pipeline addWithIndex(Pipeline to, seq_int_t idx, bool addFull=true);
		Pipeline operator|(Pipeline to);
		Pipeline operator|(PipelineList& to);
		Pipeline operator|(Var& to);
		Pipeline operator&(PipelineList& to);
		Pipeline operator||(Pipeline to);
		Pipeline operator&&(PipelineList& to);
	};

	struct PipelineAggregatorProxy {
		PipelineAggregator& aggr;
		seq_int_t idx;
		PipelineAggregatorProxy(PipelineAggregator& aggr, seq_int_t idx);
		explicit PipelineAggregatorProxy(PipelineAggregator& aggr);
		Pipeline operator|(Pipeline to);
		Pipeline operator|(PipelineList& to);
		Pipeline operator|(Var& to);
		Pipeline operator&(PipelineList& to);
		Pipeline operator||(Pipeline to);
		Pipeline operator&&(PipelineList& to);
	};

	class SeqModule : public BaseFunc {
	private:
		bool standalone;
		std::vector<std::string> sources;
		std::array<ValMap, io::MAX_INPUTS> outs;
		Var argsVar;

		friend PipelineAggregator;
	public:
		explicit SeqModule(bool standalone=false);
		~SeqModule();

		PipelineAggregator main;
		PipelineAggregator once;
		PipelineAggregator last;

		io::DataBlock *data;

		void source(std::string s);
		Var *getArgsVar();

		template<typename ...T>
		void source(std::string s, T... etc)
		{
			source(std::move(s));
			source(etc...);
		}

		void codegen(llvm::Module *module) override;
		void codegenCall(BaseFunc *base,
		                 ValMap ins,
		                 ValMap outs,
		                 llvm::BasicBlock *block) override;
		void add(Pipeline pipeline) override;
		void execute(const std::vector<std::string>& args={}, bool debug=false);

		Pipeline operator|(Pipeline to);
		Pipeline operator|(PipelineList& to);
		Pipeline operator|(Var& to);
		Pipeline operator&(PipelineList& to);
		Pipeline operator||(Pipeline to);
		Pipeline operator&&(PipelineList& to);

		PipelineAggregatorProxy operator[](unsigned idx);
	};

}

#endif /* SEQ_SEQ_H */
