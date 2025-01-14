classdef Lookup_Table_Method<handle
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties        
        check_lt;       %%Check Node Lookup Table        
        Max_Iteration;
        LLRTable;
        H;
        vari_node_transform;
        check_node_transform;
        dc_max;
        dv_max;
        vari_lt;
        p_flag;
        p_bits;
        T;
    end
    properties (SetAccess=private)
        CheckTable=[];     %%Check Node Table
        VariTable=[];
        check_degree=[];
        vari_degree=[];       
        C2VTable=[];
        V2CTable=[];
        CWLength=[];
        InfoLength=[];
        CheckNum=[];  
    end

    
    methods
        function obj = Lookup_Table_Method(check_lt,vari_lt,max_iteration,LLR_Table,H,vari_node_transform,check_node_transform,dc_max,dv_max,p_flag,p_bits,T)
            %UNTITLED Construct an instance of this class
            %   Initialization                       
            obj.check_lt=check_lt;
            obj.vari_lt=vari_lt;
            obj.Max_Iteration=max_iteration;
            obj.LLRTable=LLR_Table;
            obj.H=H;
            obj.vari_node_transform=vari_node_transform;
            obj.check_node_transform=check_node_transform;
            obj.dc_max=dc_max;
            obj.dv_max=dv_max;
            obj.p_bits=p_bits;
            obj.p_flag=p_flag;
            obj.T=T;  
            
        end
        
        function  Parity_check_matrix_analysis(obj)
            %METHOD1 Summary of this method goes here
            %   Construct Variable nad Check Node Table 
            [k,n]=size(obj.H);
            obj.CheckTable=zeros(k,obj.dc_max);
            obj.VariTable=zeros(n,obj.dv_max);
            obj.check_degree=zeros(1,k);
            obj.vari_degree=zeros(1,n);
            for ii=1:k
                M=find(obj.H(ii,:)~=0); 
                obj.CheckTable(ii,1:length(M))=M;
                obj.check_degree(ii)=length(M);
            end            
            for ii=1:n
                M=find(obj.H(:,ii)~=0).';
                obj.VariTable(ii,1:length(M))=M;
                obj.vari_degree(ii)=length(M);
            end
            obj.CWLength=n;
            obj.InfoLength=n-k;
            obj.CheckNum=k;            
        end
        
        function [FinalBits_R3] = lookuptable_decoder(obj,trans_bits,QuanChan)
            FinalDisOutput=zeros(1,obj.CWLength);
            FirstV2CTable=zeros(obj.CWLength-obj.InfoLength,obj.CWLength);  %%k*n matrix
            
            for ii=1:obj.CWLength
                FirstV2CTable(:,ii)=ones(obj.CWLength-obj.InfoLength,1)*(QuanChan(ii));
            end
            obj.C2VTable=zeros(obj.CWLength-obj.InfoLength,obj.CWLength); %%k*n matrix
            obj.V2CTable=obj.C2VTable;
            for ss=1:obj.Max_Iteration
                Vari_node_transform=obj.vari_node_transform(:,:,ss);
                Check_node_transform=obj.check_node_transform(:,:,ss);
                %% c -> v
                for ii =1:obj.CheckNum                      %%Note: ii is the index of check node
                    Dc=obj.check_degree(ii);
                    VnodesC=obj.CheckTable(ii,1:Dc);        %%Obtain the varaible node connected by ii
                    Msg=zeros(1:length(Dc));
                    for jj=1:Dc
                        Neighbors=VnodesC;
                        Neighbors(jj)=[];                   %% delete itself
                        if ss==1                            %% obtain input msgs
                            Neighbor_Cluster=FirstV2CTable(ii,Neighbors);
                        else
                            Neighbor_Cluster=obj.V2CTable(ii,Neighbors);
                        end
                        msg_noalignment_c=Trace( Neighbor_Cluster,obj.check_lt(ss,1:Dc-2),0);
                        if (msg_noalignment_c~=0)
                            Msg(jj)=Check_node_transform(Dc,msg_noalignment_c);
                        else
                            Msg(jj)=0;
                        end
                    end
                     obj.C2VTable(ii,VnodesC)=Msg;
                end
                %% v -> c         
                for ii =1:obj.CWLength
                    Dv=obj.vari_degree(ii);
                    CNodesV=obj.VariTable(ii,1:Dv);
                    for jj=1:Dv
                        CheNode=CNodesV(jj);
                        Neighbors=CNodesV;
                        Neighbors(jj)=[];
                        Neighbor_Cluster=obj.C2VTable(Neighbors,ii).';
                        msg_noalignment_v=Trace([QuanChan(ii) Neighbor_Cluster],obj.vari_lt(ss,1:Dv-1),1);
                        if msg_noalignment_v ==1
                            a=1;
                        end
                        if msg_noalignment_v~=0
                            obj.V2CTable(CheNode,ii)=Vari_node_transform(Dv,msg_noalignment_v);
                        else
                            obj.V2CTable(CheNode,ii)=0;
                        end
                    end
                end
                FirstV2CTable=obj.V2CTable;           
                for ii =1:obj.CWLength
                    Dv=obj.vari_degree(ii);
                    CNodesV=obj.VariTable(ii,1:Dv);
                    Neighbor_Cluster=ObtainInput( obj.C2VTable(:,ii).',CNodesV );
                    FinalDisOutput(ii)=Trace([QuanChan(ii) Neighbor_Cluster],obj.vari_lt(ss,1:Dv),1);
                end
                subplot(1,2,1);
                histogram(FinalDisOutput);
                xlim([0 18]);
                ylim([0 10000])
                subplot(1,2,2);
                plot(FinalDisOutput);
                
                [FinalBits_R3] =IB_bitdiscit_decision(obj.LLRTable, FinalDisOutput,obj.vari_degree);   
                if(sum(FinalBits_R3~=trans_bits)==0)
                    break;
                end                                
            end             
        end      
   
        function [BER,FER]=Simulation(obj,Eb_N0,Runtime,Max,Min,ProbConTY,CodeRate)
            cwLength=obj.CWLength;
            bit_error=zeros(1,Runtime);
            frame_error=zeros(1,Runtime);
            p_flag_loc=obj.p_flag;
            p_bits_loc=obj.p_bits;
            T_loc=obj.T;
            for mm=1:Runtime
                trans_bits=zeros(1,cwLength);
                CodeWord=-2*trans_bits+1;                                           % Convert Binary Bits to Codeword
                sigma2=10^(-0.1*Eb_N0)/(2*CodeRate);
                TransCD=CodeWord+normrnd(0,sqrt(sigma2),1,cwLength);                % add noise
                [ DisCW ] = Discrete( TransCD,Max,Min,2000 );
                [QuanChan]=Channel_Mapping( DisCW,ProbConTY );                      % Discrete Input with cardi T
                if p_flag_loc==1
                    QuanChan(1:p_bits_loc)=binornd(1,0.5,[1,p_bits_loc])+1;
                end
                [FinalBits_R3] = lookuptable_decoder(obj,trans_bits,QuanChan);
                bit_error(mm)=sum(trans_bits~=FinalBits_R3);
                if bit_error(mm) ~= 0
                    frame_error(mm)=1;
                end
                display(['under:' num2str(Eb_N0) 'has run'  num2str(mm/Runtime)]);
            end
            BER=sum(bit_error)/(Runtime*obj.CWLength);
            FER=sum(frame_error)/Runtime;            
        end
        
        
    end
end

